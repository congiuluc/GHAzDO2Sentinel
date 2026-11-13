"""Offline ARM policy/wiring checks. Requires Python 3 and Azure CLI with Bicep."""

import ast
import copy
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


def policy(value, parameters, variables=None, index=None):
    """Evaluate only the ARM expression subset used by networking policies."""
    if not isinstance(value, str) or not value.startswith("["):
        return value
    expression = re.sub(r"\b(if|not|or)\(", r"arm_\1(", value[1:-1])

    def visit(node):
        if isinstance(node, ast.Constant):
            return node.value
        if isinstance(node, ast.Attribute):
            return visit(node.value)[node.attr]
        if isinstance(node, ast.Subscript):
            return visit(node.value)[visit(node.slice)]
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            name = node.func.id
            if name == "arm_if":
                return visit(node.args[1] if visit(node.args[0]) else node.args[2])
            functions = {
                "parameters": lambda key: parameters[key],
                "variables": lambda key: policy(variables[key], parameters, variables, index),
                "copyIndex": lambda: index,
                "null": lambda: None,
                "false": lambda: False,
                "equals": lambda a, b: a == b,
                "arm_not": lambda a: not a,
                "arm_or": lambda a, b: a or b,
                "empty": lambda a: a is None or len(a) == 0,
                "tryGet": lambda obj, key: None if obj is None else obj.get(key),
                "coalesce": lambda *args: next(a for a in args if a is not None),
                "split": lambda text, separator: text.split(separator),
                "subscription": lambda: {"subscriptionId": "app-subscription"},
                "resourceGroup": lambda: {"name": "app-resource-group"},
            }
            return functions[name](*(visit(arg) for arg in node.args))
        raise AssertionError(f"Unsupported policy expression: {ast.dump(node)}")

    return visit(ast.parse(expression, mode="eval").body)


class PrivateNetworkingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        az = shutil.which("az")
        if az is None:
            raise RuntimeError("Azure CLI is required; install it before running these tests.")
        with tempfile.TemporaryDirectory() as output:
            template = Path(output) / "main.json"
            parameters = Path(output) / "private.json"
            for command in [
                ["build", "--file", str(ROOT / "infra" / "main.bicep"), "--outfile", str(template)],
                ["build-params", "--file", str(ROOT / "infra" / "private-network.example.bicepparam"),
                 "--outfile", str(parameters)],
            ]:
                result = subprocess.run([az, "bicep", *command], capture_output=True, text=True)
                if result.returncode != 0:
                    raise RuntimeError(f"Bicep {command[0]} failed:\n{result.stdout}\n{result.stderr}")
            cls.template = json.loads(template.read_text(encoding="utf-8-sig"))
            cls.private = json.loads(parameters.read_text(encoding="utf-8-sig"))["parameters"]["privateNetwork"]["value"]
        cls.modules = cls.template["resources"]
        cls.network_modules = [
            "dataPrivateEndpoints", "functionPrivateEndpoint", "dcePrivateLink", "appInsightsPrivateLink",
        ]

    def root_policy(self, expression, configuration):
        return policy(expression, {"privateNetwork": configuration}, self.template["variables"])

    def module_parameter(self, module, name, configuration):
        expression = self.modules[module]["properties"]["parameters"][name]["value"]
        return self.root_policy(expression, configuration)

    def deployments(self, template):
        resources = template["resources"]
        if isinstance(resources, dict):
            resources = resources.values()
        return [resource for resource in resources if not resource.get("existing", False)]

    def owner(self, module, resource_type):
        """Return (deployment, resource) for the first resource of the type below a root module."""
        pending = [self.modules[module]]
        while pending:
            deployment = pending.pop(0)
            for resource in self.deployments(deployment["properties"]["template"]):
                if resource["type"] == resource_type:
                    return deployment, resource
                if resource["type"] == "Microsoft.Resources/deployments":
                    pending.append(resource)
        raise AssertionError(f"{resource_type} not found below {module}")

    def resource(self, module, resource_type):
        return self.owner(module, resource_type)[1]

    def resources(self, module):
        return self.deployments(self.modules[module]["properties"]["template"])

    def test_public_default_creates_no_network_resources_or_cross_scope_lookup(self):
        self.assertTrue(self.template["parameters"]["privateNetwork"]["nullable"])
        for module in self.network_modules:
            self.assertFalse(self.root_policy(self.modules[module]["condition"], None))
        for module in ["dcePrivateLink", "appInsightsPrivateLink"]:
            scope = self.modules[module]
            self.assertEqual(self.root_policy(scope["subscriptionId"], None), "app-subscription")
            self.assertEqual(self.root_policy(scope["resourceGroup"], None), "app-resource-group")

    def test_private_mode_closes_data_endpoints_and_monitor_access(self):
        cases = [
            ("storage", "Microsoft.Storage/storageAccounts", ["publicNetworkAccess"]),
            ("keyVault", "Microsoft.KeyVault/vaults", ["publicNetworkAccess"]),
            ("monitoring", "Microsoft.Insights/components",
             ["publicNetworkAccessForIngestion", "publicNetworkAccessForQuery"]),
        ]
        for configuration, expected in [(None, "Enabled"), (self.private, "Disabled")]:
            for module, resource_type, properties in cases:
                enabled = self.module_parameter(module, "privateNetworkingEnabled", configuration)
                for name in properties:
                    with self.subTest(module=module, property=name, private=enabled):
                        expression = self.resource(module, resource_type)["properties"][name]
                        self.assertEqual(policy(expression, {"privateNetworkingEnabled": enabled}), expected)

    def test_service_bus_premium_and_public_exception_are_independent(self):
        private_without_exception = copy.deepcopy(self.private)
        private_without_exception.pop("allowPublicServiceBusAccess")
        hybrid = {**self.private, "allowPublicServiceBusAccess": True}
        resource = self.resource("serviceBusNamespace", "Microsoft.ServiceBus/namespaces")
        for configuration, sku, access in [
            (None, "Standard", "Enabled"),
            (self.private, "Premium", "Disabled"),
            (private_without_exception, "Premium", "Disabled"),
            (hybrid, "Premium", "Enabled"),
        ]:
            with self.subTest(sku=sku, access=access):
                parameters = {
                    name: self.module_parameter("serviceBusNamespace", name, configuration)
                    for name in ["privateNetworkingEnabled", "allowPublicAccess"]
                }
                self.assertEqual(policy(resource["sku"]["name"], parameters), sku)
                self.assertEqual(policy(resource["sku"]["capacity"], parameters), 1 if sku == "Premium" else 0)
                self.assertEqual(policy(resource["properties"]["publicNetworkAccess"], parameters), access)

    def test_function_joins_existing_subnet_only_in_private_mode(self):
        properties = self.resource("functionApp", "Microsoft.Web/sites")["properties"]
        for configuration, access in [(None, "Enabled"), (self.private, "Disabled")]:
            subnet = self.module_parameter("functionApp", "integrationSubnetId", configuration)
            parameters = {"integrationSubnetId": subnet}
            self.assertEqual(policy(properties["publicNetworkAccess"], parameters), access)
            self.assertEqual(policy(properties["virtualNetworkSubnetId"], parameters), subnet or None)
        self.assertEqual(subnet, self.private["functionIntegrationSubnetId"])
        dependencies = self.modules["functionApp"]["dependsOn"]
        for module in ["dataPrivateEndpoints", "dcePrivateLink", "appInsightsPrivateLink"]:
            self.assertIn(module, dependencies)
        self.assertNotIn("functionPrivateEndpoint", dependencies)

    def test_six_private_endpoints_use_existing_subnet_and_dns_zones(self):
        expected = {
            "blob": "blob", "queue": "queue", "table": "table",
            "namespace": "serviceBus", "vault": "keyVault", "sites": "sites",
        }
        variables = self.template["variables"]
        found = {}
        for module in ["dataPrivateEndpoints", "functionPrivateEndpoint"]:
            deployment = self.modules[module]
            self.assertTrue(self.root_policy(deployment["condition"], self.private))
            count = len(variables["dataPrivateEndpointDefinitions"]) if "copy" in deployment else 1
            for index in range(count):
                parameters = deployment["properties"]["parameters"]
                evaluate = lambda name: policy(parameters[name]["value"], {"privateNetwork": self.private},
                                               variables, index)
                self.assertEqual(evaluate("subnetId"), self.private["privateEndpointSubnetId"])
                found[evaluate("groupId")] = evaluate("privateDnsZoneId")
            types = {resource["type"] for resource in self.resources(module)}
            self.assertEqual(types, {"Microsoft.Network/privateEndpoints",
                                    "Microsoft.Network/privateEndpoints/privateDnsZoneGroups"})
        self.assertEqual(found, {group: self.private["privateDnsZoneResourceIds"][zone]
                                 for group, zone in expected.items()})

    def test_private_ingestion_uses_dce_and_existing_ampls_without_recreating_workspace(self):
        workspace = self.modules["workspace"]["properties"]["template"]
        dce_module, dce = self.owner("workspace", "Microsoft.Insights/dataCollectionEndpoints")
        self.assertFalse(policy(dce_module["condition"], {"privateNetworkingEnabled": False}))
        self.assertTrue(policy(dce_module["condition"], {"privateNetworkingEnabled": True}))
        self.assertEqual(dce["properties"]["networkAcls"]["publicNetworkAccess"], "Disabled")
        dcr_module, dcr = self.owner("workspace", "Microsoft.Insights/dataCollectionRules")
        self.assertIn("ghas-dce", json.dumps(dcr_module["properties"]["parameters"]["dataCollectionEndpointId"]))
        self.assertIn("dataCollectionEndpointId", dcr["properties"]["dataCollectionEndpointId"])
        endpoint = workspace["outputs"]["logsIngestionEndpoint"]["value"]
        self.assertIn("if(parameters('privateNetworkingEnabled')", endpoint)
        self.assertIn("ghas-dce", endpoint)
        self.assertIn("logsIngestionEndpoint", endpoint)
        nested = [resource["type"] for module in self.resources("workspace")
                  for resource in self.deployments(module["properties"]["template"])]
        self.assertNotIn("Microsoft.OperationalInsights/workspaces", nested)
        segments = self.private["monitorPrivateLinkScopeResourceId"].split("/")
        for module, source in [("dcePrivateLink", "dataCollectionEndpointResourceId"),
                               ("appInsightsPrivateLink", "monitoring")]:
            deployment = self.modules[module]
            self.assertIn(source, deployment["properties"]["parameters"]["linkedResourceId"]["value"])
            self.assertEqual(self.root_policy(deployment["subscriptionId"], self.private), segments[2])
            self.assertEqual(self.root_policy(deployment["resourceGroup"], self.private), segments[4])
            types = {resource["type"] for resource in self.resources(module)}
            self.assertEqual(types, {"Microsoft.Insights/privateLinkScopes/scopedResources"})
        self.assertIn("dcePrivateLink", self.modules["appInsightsPrivateLink"]["dependsOn"])

if __name__ == "__main__":
    unittest.main()
