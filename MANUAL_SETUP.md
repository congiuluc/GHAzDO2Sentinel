# Configurazione manuale tramite interfaccia grafica

Questa guida descrive come creare e configurare **manualmente**, dal portale Azure, dal portale Microsoft Sentinel/Defender e da Azure DevOps, tutte le risorse che `infra/main.bicep` crea automaticamente. Usala quando non puoi usare `azd`, Azure CLI o pipeline IaC.

> I nomi dei menu del portale possono cambiare leggermente nel tempo. In caso di differenze, cerca la voce equivalente. Le impostazioni da applicare sono quelle elencate nelle tabelle.

> Ogni passaggio include un blocco **Alternativa con Azure CLI** con i comandi equivalenti. Requisiti e variabili comuni sono nel [passaggio 0](#0-prerequisiti-e-valori-da-annotare).

## Indice

0. [Prerequisiti e valori da annotare](#0-prerequisiti-e-valori-da-annotare)
1. [Alternativa rapida: modello personalizzato dal portale](#1-alternativa-rapida-modello-personalizzato-dal-portale)
2. [Gruppo di risorse](#2-gruppo-di-risorse)
3. [Identità gestita assegnata dall'utente](#3-identità-gestita-assegnata-dallutente)
4. [Storage account](#4-storage-account)
5. [Application Insights](#5-application-insights)
6. [Service Bus: namespace, coda, SAS e RBAC](#6-service-bus-namespace-coda-sas-e-rbac)
7. [Key Vault](#7-key-vault)
8. [Workspace Sentinel: DCE, tabella personalizzata e DCR](#8-workspace-sentinel-dce-tabella-personalizzata-e-dcr)
9. [Function App Flex Consumption](#9-function-app-flex-consumption)
10. [Pubblicazione del codice della Function](#10-pubblicazione-del-codice-della-function)
11. [Workbook Sentinel](#11-workbook-sentinel)
12. [Regola di analisi Sentinel (facoltativa)](#12-regola-di-analisi-sentinel-facoltativa)
13. [Service hook Azure DevOps](#13-service-hook-azure-devops)
14. [Verifica end-to-end](#14-verifica-end-to-end)
15. [Rete privata hub & spoke (facoltativa)](#15-rete-privata-hub--spoke-facoltativa)
16. [Riepilogo delle assegnazioni di ruolo](#16-riepilogo-delle-assegnazioni-di-ruolo)

---

## 0. Prerequisiti e valori da annotare

### Prerequisiti

- Workspace Log Analytics esistente con **Microsoft Sentinel abilitato**.
- Organizzazione Azure DevOps Services con **Advanced Security** attivo sui repository.
- Permessi Azure:
  - sul gruppo di risorse applicativo: creazione risorse e assegnazione ruoli (ad esempio **Owner**, oppure **Contributor** + **Role Based Access Control Administrator**/**User Access Administrator**);
  - sul gruppo di risorse del workspace: creazione di DCE, DCR, tabelle, workbook e regole Sentinel, più assegnazione ruoli sulla DCR (ad esempio **Contributor** + **Microsoft Sentinel Contributor** + **Role Based Access Control Administrator**).
- Permessi Azure DevOps: **Project Administrator** (o permessi *Edit/View subscriptions* sui service hook).
- Per la pubblicazione del codice: .NET 10 SDK e Visual Studio Code con estensione **Azure Functions**, oppure Visual Studio.

### Scheda dei valori

Compila questa tabella durante la procedura: i valori servono nei passaggi successivi.

| Valore | Esempio | Dove si ottiene |
| --- | --- | --- |
| Sottoscrizione applicativa | `xxxxxxxx-...` | Passaggio 2 |
| Gruppo di risorse applicativo | `rg-ghas-sentinel-prod` | Passaggio 2 |
| Area applicativa | `West Europe` | Passaggio 2 (deve supportare Flex Consumption) |
| Sottoscrizione / gruppo di risorse / nome / area del workspace | `rg-sentinel`, `law-sentinel`, `West Europe` | Workspace esistente |
| Nome identità gestita | `id-ghas-prod` | Passaggio 3 |
| Client ID dell'identità | GUID | Passaggio 3, **Overview** |
| Nome storage account | `stghasprod001` | Passaggio 4 |
| Nome Application Insights | `appi-ghas-prod` | Passaggio 5 |
| Namespace Service Bus | `sb-ghas-prod` | Passaggio 6 |
| Nome coda | `ghas` (obbligatorio in minuscolo, coerente con la Function e gli script) | Passaggio 6 |
| Nome Key Vault | `kv-ghas-prod` | Passaggio 7 |
| URI Logs ingestion della DCE | `https://dce-ghas-...ingest.monitor.azure.com` | Passaggio 8 |
| Immutable ID della DCR | `dcr-xxxxxxxx...` | Passaggio 8 |
| Nome stream della DCR | `Custom-GHASAlerts_CL` | Passaggio 8 |
| Nome Function App | `func-ghas-prod` | Passaggio 9 |

> I nomi di storage account, Service Bus, Key Vault e Function App devono essere **univoci a livello globale**.


### Alternativa con Azure CLI

Ogni passaggio di questa guida termina con un blocco **Alternativa con Azure CLI** che esegue le stesse operazioni da riga di comando. Requisiti:

- **PowerShell 7.4 o successivo**: i comandi usano l'operatore ternario e passano JSON tra apici singoli ad `az`, che Windows PowerShell 5.1 non gestisce correttamente;
- Azure CLI aggiornata (`az upgrade`) ed estensione `log-analytics` per la verifica del passaggio 14;
- esegui i comandi dalla radice del repository e nella stessa sessione, perché i passaggi successivi riusano le variabili.

Variabili comuni, da impostare una volta per sessione:

```powershell
az login

$appSub     = '<id-sottoscrizione-applicativa>'
$rg         = 'rg-ghas-sentinel-prod'
$location   = 'westeurope'
$wsSub      = '<id-sottoscrizione-workspace>'
$wsRg       = 'rg-sentinel'
$wsName     = 'law-sentinel'
$wsLocation = 'westeurope'
$idName     = 'id-ghas-prod'
$st         = 'stghasprod001'
$appi       = 'appi-ghas-prod'
$sb         = 'sb-ghas-prod'
$queue      = 'ghas'
$kv         = 'kv-ghas-prod'
$dcrName    = 'dcr-ghas-prod'
$func       = 'func-ghas-prod'
$stream     = 'Custom-GHASAlerts_CL'

az account set --subscription $appSub
$wsId = az monitor log-analytics workspace show --subscription $wsSub -g $wsRg -n $wsName --query id -o tsv
```

---

## 1. Alternativa rapida: modello personalizzato dal portale

Se è consentito usare un modello ARM dal portale, puoi creare quasi tutto con un'unica distribuzione e poi saltare ai passaggi [10](#10-pubblicazione-del-codice-della-function) e [13](#13-service-hook-azure-devops).

1. Rigenera `infra/main.json` dal Bicep corrente: in Visual Studio Code, con l'estensione **Bicep**, fai clic destro su `infra/main.bicep` > **Build ARM Template**. Il file `infra/main.json` presente nel repository potrebbe non essere allineato al Bicep.
2. Nel portale Azure cerca **Deploy a custom template** (Distribuisci un modello personalizzato) > **Build your own template in the editor** > **Load file** > seleziona `infra/main.json` > **Save**.
3. Seleziona sottoscrizione e gruppo di risorse applicativo, quindi compila i parametri: `environmentName`, `workspaceSubscriptionId`, `workspaceResourceGroup`, `workspaceName`, `workspaceRegion`, `enableAnalyticsRule` (`true` o `false`). Lascia `privateNetwork` vuoto per la distribuzione pubblica.
4. **Review + create** > **Create**. Al termine, apri la distribuzione > **Outputs** per leggere i nomi delle risorse.

Il resto di questa guida descrive la procedura completamente manuale, risorsa per risorsa.


### Alternativa con Azure CLI

Usa direttamente `infra/main.bicep`, senza dover rigenerare `main.json`. Crea prima il gruppo di risorse ([passaggio 2](#2-gruppo-di-risorse)).

```powershell
az deployment group create -g $rg --template-file infra/main.bicep `
  --parameters environmentName=prod workspaceSubscriptionId=$wsSub workspaceResourceGroup=$wsRg `
               workspaceName=$wsName workspaceRegion=$wsLocation enableAnalyticsRule=true `
  --query properties.outputs
```

Per la rete privata, copia `infra/private-network.example.bicepparam`, compila i valori e usa `az deployment group create -g $rg --parameters <file>.bicepparam`. Dopo la distribuzione, continua con i passaggi [10](#10-pubblicazione-del-codice-della-function) e [13](#13-service-hook-azure-devops).

---

## 2. Gruppo di risorse

1. Portale Azure > **Resource groups** > **+ Create**.
2. Seleziona la **sottoscrizione applicativa**, inserisci il nome e scegli un'**area che supporta Flex Consumption**. Preferibilmente usa la stessa area del workspace.
3. Facoltativo: aggiungi tag (ad esempio `workload=ghas-sentinel`).
4. **Review + create** > **Create**.


### Alternativa con Azure CLI

```powershell
az group create -n $rg -l $location --tags workload=ghas-sentinel
```

---

## 3. Identità gestita assegnata dall'utente

La Function usa questa identità per storage, Service Bus e Logs Ingestion API. Non vengono usate chiavi.

1. Portale > **Managed Identities** > **+ Create**.
2. Sottoscrizione, gruppo di risorse e area applicativi; nome, ad esempio `id-ghas-prod`.
3. **Review + create** > **Create**.
4. Apri l'identità > **Overview** e annota **Client ID** e **Object (principal) ID**.


### Alternativa con Azure CLI

```powershell
az identity create -g $rg -n $idName -l $location --output none
$idId          = az identity show -g $rg -n $idName --query id -o tsv
$idClientId    = az identity show -g $rg -n $idName --query clientId -o tsv
$idPrincipalId = az identity show -g $rg -n $idName --query principalId -o tsv
```

---

## 4. Storage account

Lo storage ospita lo stato dell'host Functions e il contenitore dei pacchetti di distribuzione.

### 4.1 Creazione

Portale > **Storage accounts** > **+ Create**:

| Scheda | Impostazione | Valore |
| --- | --- | --- |
| Basics | Primary service | Azure Blob Storage or Azure Data Lake Storage Gen 2 (o lascia il valore predefinito) |
| Basics | Performance | Standard |
| Basics | Redundancy | Locally-redundant storage (LRS) |
| Advanced | Require secure transfer | Abilitato |
| Advanced | Allow enabling anonymous access on individual containers | **Disabilitato** |
| Advanced | Enable storage account key access | **Abilitato temporaneamente** (vedi nota) |
| Advanced | Default to Microsoft Entra authorization in the Azure portal | Abilitato |
| Advanced | Minimum TLS version | Version 1.2 |
| Advanced | Access tier | Hot |
| Networking | Network access | Enable public access from all networks (per la distribuzione pubblica) |

> **Nota sulle chiavi:** il modello Bicep disabilita l'accesso con chiave condivisa. Il wizard del portale per la Function App, però, configura inizialmente `AzureWebJobsStorage` con una stringa di connessione. Lascia temporaneamente abilitato l'accesso con chiave e disabilitalo al [passaggio 9.6](#96-disabilitazione-dellaccesso-con-chiave-allo-storage), dopo il passaggio alle identità gestite.

### 4.2 Contenitore dei pacchetti

1. Apri lo storage account > **Data storage** > **Containers** > **+ Container**.
2. Nome: `function-packages`; livello di accesso anonimo: **Private (no anonymous access)**.
3. **Create**.

> Per gestire i contenitori con l'autenticazione Microsoft Entra, il tuo utente deve avere almeno **Storage Blob Data Contributor** sullo storage account.

### 4.3 Ruoli per l'identità gestita

Storage account > **Access control (IAM)** > **+ Add** > **Add role assignment**. Ripeti per ognuno dei ruoli seguenti, selezionando **Managed identity** > **User-assigned managed identity** > l'identità del passaggio 3:

- **Storage Blob Data Owner**
- **Storage Blob Data Contributor**
- **Storage Queue Data Contributor**
- **Storage Table Data Contributor**


### Alternativa con Azure CLI

L'accesso con chiave resta abilitato temporaneamente e viene disabilitato al passaggio 9, come nella procedura del portale. Il contenitore viene creato tramite il piano di controllo (`container-rm`), quindi non serve un ruolo dati per l'utente.

```powershell
az storage account create -g $rg -n $st -l $location --kind StorageV2 --sku Standard_LRS `
  --access-tier Hot --https-only true --min-tls-version TLS1_2 `
  --allow-blob-public-access false --allow-shared-key-access true --public-network-access Enabled
$stId = az storage account show -g $rg -n $st --query id -o tsv

az storage container-rm create -g $rg --storage-account $st -n function-packages --public-access off

foreach ($role in 'Storage Blob Data Owner', 'Storage Blob Data Contributor',
                  'Storage Queue Data Contributor', 'Storage Table Data Contributor') {
  az role assignment create --assignee-object-id $idPrincipalId --assignee-principal-type ServicePrincipal `
    --role $role --scope $stId --output none
}
```

---

## 5. Application Insights

1. Portale > **Application Insights** > **+ Create**.
2. Gruppo di risorse e area applicativi; nome, ad esempio `appi-ghas-prod`.
3. **Resource mode**: Workspace-based; **Log Analytics Workspace**: seleziona il **workspace Sentinel** (anche se si trova in un'altra sottoscrizione).
4. **Review + create** > **Create**.


### Alternativa con Azure CLI

```powershell
az monitor app-insights component create -g $rg --app $appi -l $location `
  --kind web --application-type web --workspace $wsId
```

---

## 6. Service Bus: namespace, coda, SAS e RBAC

### 6.1 Namespace

Portale > **Service Bus** > **+ Create**:

| Scheda | Impostazione | Valore |
| --- | --- | --- |
| Basics | Pricing tier | **Standard** (Premium solo per la rete privata, vedi [passaggio 15](#15-rete-privata-hub--spoke-facoltativa)) |
| Advanced | Minimum TLS version | 1.2 |
| Advanced | Local Authentication | **Enabled** (necessario per la modalità SAS dei service hook) |
| Networking | Connectivity method | Public access |

**Review + create** > **Create**.

### 6.2 Coda

Namespace > **Entities** > **Queues** > **+ Queue**:

| Impostazione | Valore |
| --- | --- |
| Name | `ghas` |
| Max delivery count | `10` |
| Message time to live | `14` giorni |
| Lock duration | `5` minuti |
| Enable dead lettering on message expiration | Abilitato |
| Enable duplicate detection | Abilitato, finestra di `10` minuti |
| Enable sessions / partitioning | Disabilitato |

> Il rilevamento dei duplicati può essere impostato **solo alla creazione** della coda.

### 6.3 Criterio SAS di sola invio (solo modalità SAS)

1. Apri la coda `ghas` > **Settings** > **Shared access policies** > **+ Add**.
2. Nome: `sendOnly`; seleziona **solo Send**; **Create**.
3. Apri `sendOnly` e copia la **Primary Connection String** solo quando serve nel [passaggio 13](#13-service-hook-azure-devops). Rimuovi il suffisso `;EntityPath=ghas` prima di usarla nel service hook.

### 6.4 Ruolo di ricezione per la Function

Coda `ghas` > **Access control (IAM)** > **+ Add** > **Add role assignment** > **Azure Service Bus Data Receiver** > **Managed identity** > l'identità del passaggio 3 > **Review + assign**.

### 6.5 Impostazione di diagnostica

1. Namespace > **Monitoring** > **Diagnostic settings** > **+ Add diagnostic setting**.
2. Nome: `servicebus-to-sentinel`.
3. Seleziona il gruppo di categorie **allLogs** e la categoria **AllMetrics**.
4. **Destination details** > **Send to Log Analytics workspace** > workspace Sentinel.
5. **Save**.


### Alternativa con Azure CLI

```powershell
az servicebus namespace create -g $rg -n $sb -l $location --sku Standard `
  --min-tls 1.2 --disable-local-auth false --public-network-access Enabled

az servicebus queue create -g $rg --namespace-name $sb -n $queue `
  --max-delivery-count 10 --default-message-time-to-live P14D --lock-duration PT5M `
  --enable-dead-lettering-on-message-expiration true `
  --enable-duplicate-detection true --duplicate-detection-history-time-window PT10M

az servicebus queue authorization-rule create -g $rg --namespace-name $sb --queue-name $queue `
  -n sendOnly --rights Send

$queueId = az servicebus queue show -g $rg --namespace-name $sb -n $queue --query id -o tsv
az role assignment create --assignee-object-id $idPrincipalId --assignee-principal-type ServicePrincipal `
  --role 'Azure Service Bus Data Receiver' --scope $queueId --output none

$sbId = az servicebus namespace show -g $rg -n $sb --query id -o tsv
az monitor diagnostic-settings create -n servicebus-to-sentinel --resource $sbId --workspace $wsId `
  --logs '[{"categoryGroup":"allLogs","enabled":true}]' `
  --metrics '[{"category":"AllMetrics","enabled":true}]'
```

---

## 7. Key Vault

Usato facoltativamente per conservare la stringa di connessione SAS dei service hook.

1. Portale > **Key vaults** > **+ Create**.
2. **Basics**: gruppo di risorse e area applicativi; **Pricing tier**: Standard; **Days to retain deleted vaults**: `7`; **Purge protection**: disabilitata per la distribuzione pubblica (abilitata per quella privata; non può essere disabilitata in seguito).
3. **Access configuration** > **Permission model**: **Azure role-based access control**.
4. **Networking**: accesso pubblico da tutte le reti (distribuzione pubblica).
5. **Review + create** > **Create**.
6. Per salvare segreti, assegna al tuo utente **Key Vault Secrets Officer** sul vault (**Access control (IAM)**).

Per salvare la stringa SAS: Key Vault > **Objects** > **Secrets** > **+ Generate/Import** > nome `ghas-service-hook-send` > valore: stringa di connessione senza `EntityPath` > **Create**. Non condividere né incollare questo valore in file o ticket.


### Alternativa con Azure CLI

```powershell
az keyvault create -g $rg -n $kv -l $location --sku standard --enable-rbac-authorization true `
  --retention-days 7 --public-network-access Enabled --default-action Allow --bypass None
$kvId = az keyvault show -n $kv --query id -o tsv

$me = az ad signed-in-user show --query id -o tsv
az role assignment create --assignee-object-id $me --assignee-principal-type User `
  --role 'Key Vault Secrets Officer' --scope $kvId --output none
```

Per salvare la stringa SAS senza stamparla, usa lo script del [passaggio 13](#13-service-hook-azure-devops) con `-KeyVaultName`, oppure:

```powershell
$sas = (az servicebus queue authorization-rule keys list -g $rg --namespace-name $sb --queue-name $queue `
  -n sendOnly --query primaryConnectionString -o tsv) -replace ';EntityPath=[^;]*', ''
az keyvault secret set --vault-name $kv -n ghas-service-hook-send --value $sas --output none
Remove-Variable sas
```

---

## 8. Workspace Sentinel: DCE, tabella personalizzata e DCR

Queste risorse vanno create nel **gruppo di risorse e nell'area del workspace**. Il wizard del portale per le tabelle personalizzate richiede una DCE.

### 8.1 Data Collection Endpoint (DCE)

1. Portale > **Monitor** > **Settings** > **Data Collection Endpoints** > **+ Create**.
2. Nome, ad esempio `dce-ghas-prod`; sottoscrizione e gruppo di risorse del workspace; **area uguale al workspace**.
3. **Review + create** > **Create**.
4. Apri la DCE > **Overview** e annota **Logs Ingestion** (URI).

### 8.2 Tabella `GHASAlerts_CL` e DCR

1. Portale > **Log Analytics workspaces** > workspace Sentinel > **Settings** > **Tables** > **+ Create** > **New custom log (DCR-based)**.
2. **Table name**: `GHASAlerts` (il portale aggiunge automaticamente `_CL`).
3. **Data collection rule**: **Create a new data collection rule**; sottoscrizione e gruppo di risorse del workspace; nome, ad esempio `dcr-ghas-prod`.
4. **Data collection endpoint**: la DCE del passaggio 8.1. **Next**.
5. **Browse for files** > seleziona [`sentinel/ghas-table-sample.json`](sentinel/ghas-table-sample.json) dal repository. Il file contiene solo dati fittizi che servono a definire lo schema; non vengono inseriti nella tabella.
6. Seleziona **Transformation editor**, incolla la trasformazione seguente, **Run** e poi **Apply**:

   ```kusto
   source
   | extend
       TimeGenerated = todatetime(TimeGenerated),
       AlertId = tolong(AlertId),
       IntroducedDate = todatetime(IntroducedDate),
       FirstSeenDate = todatetime(FirstSeenDate),
       LastSeenDate = todatetime(LastSeenDate),
       FixedDate = todatetime(FixedDate),
       PhysicalLocations = todynamic(PhysicalLocations),
       LogicalLocations = todynamic(LogicalLocations),
       Tools = todynamic(Tools),
       RawEvent = todynamic(RawEvent)
   | project
       TimeGenerated, EventId, EventType, EventAction, OrganizationUrl,
       ProjectId, ProjectName, RepositoryName, RepositoryUrl, GitRef,
       AlertId, AlertType, Severity, Title, State, ToolName,
       RuleId, RuleName, RuleHelp,
       IntroducedDate, FirstSeenDate, LastSeenDate, FixedDate,
       DismissalType, DismissalMessage, StateChangedBy, AlertUrl,
       PhysicalLocations, LogicalLocations, Tools, RawEvent
   ```

7. Verifica lo schema risultante. I tipi devono essere:

   | Colonne | Tipo |
   | --- | --- |
   | `TimeGenerated`, `IntroducedDate`, `FirstSeenDate`, `LastSeenDate`, `FixedDate` | datetime |
   | `AlertId` | long |
   | `PhysicalLocations`, `LogicalLocations`, `Tools`, `RawEvent` | dynamic |
   | Tutte le altre | string |

8. **Next** > **Create**.

### 8.3 Valori della DCR

1. Portale > **Monitor** > **Data Collection Rules** > la DCR creata > **Overview** > **JSON View**.
2. Annota:
   - `immutableId` (inizia con `dcr-`);
   - il nome dello stream in `streamDeclarations` (atteso `Custom-GHASAlerts_CL`). Se il nome è diverso, usa quello mostrato nel JSON.
3. Verifica che `dataCollectionEndpointId` punti alla DCE del passaggio 8.1.

### 8.4 Autorizzazione all'invio dei log

DCR > **Access control (IAM)** > **+ Add** > **Add role assignment** > **Monitoring Metrics Publisher** > **Managed identity** > l'identità del passaggio 3 > **Review + assign**.

> La propagazione dell'assegnazione può richiedere fino a 30 minuti. Nel frattempo, la Function potrebbe ricevere errori `403`; i messaggi vengono ritentati da Service Bus.


### Alternativa con Azure CLI

A differenza del portale, la CLI non richiede una DCE nella distribuzione pubblica: la DCR viene creata con `kind: Direct` e usa il proprio endpoint di ingestione, come in `infra/workspace.bicep`. DCR e altre risorse Sentinel usano `az rest` con le stesse versioni API del Bicep, quindi non servono estensioni aggiuntive.

```powershell
$columns = [ordered]@{
  TimeGenerated = 'datetime'; EventId = 'string'; EventType = 'string'; EventAction = 'string'
  OrganizationUrl = 'string'; ProjectId = 'string'; ProjectName = 'string'; RepositoryName = 'string'
  RepositoryUrl = 'string'; GitRef = 'string'; AlertId = 'long'; AlertType = 'string'
  Severity = 'string'; Title = 'string'; State = 'string'; ToolName = 'string'
  RuleId = 'string'; RuleName = 'string'; RuleHelp = 'string'
  IntroducedDate = 'datetime'; FirstSeenDate = 'datetime'; LastSeenDate = 'datetime'; FixedDate = 'datetime'
  DismissalType = 'string'; DismissalMessage = 'string'; StateChangedBy = 'string'; AlertUrl = 'string'
  PhysicalLocations = 'dynamic'; LogicalLocations = 'dynamic'; Tools = 'dynamic'; RawEvent = 'dynamic'
}

# Tabella GHASAlerts_CL
$tableColumns = $columns.GetEnumerator() | ForEach-Object {
  '{0}={1}' -f $_.Key, ($_.Value -eq 'datetime' ? 'dateTime' : $_.Value)
}
az monitor log-analytics workspace table create --subscription $wsSub -g $wsRg --workspace-name $wsName `
  -n GHASAlerts_CL --columns @tableColumns --output none

# DCR (kind Direct, senza DCE)
$dcrId = "/subscriptions/$wsSub/resourceGroups/$wsRg/providers/Microsoft.Insights/dataCollectionRules/$dcrName"
$dcrUrl = "https://management.azure.com${dcrId}?api-version=2023-03-11"
$streamColumns = @($columns.GetEnumerator() | ForEach-Object { @{ name = $_.Key; type = $_.Value } })
@{
  location   = $wsLocation
  kind       = 'Direct'
  properties = @{
    streamDeclarations = @{ $stream = @{ columns = $streamColumns } }
    destinations       = @{ logAnalytics = @(@{ name = 'sentinelWorkspace'; workspaceResourceId = $wsId }) }
    dataFlows          = @(@{
      streams = @($stream); destinations = @('sentinelWorkspace')
      outputStream = $stream; transformKql = 'source'
    })
  }
} | ConvertTo-Json -Depth 10 | Set-Content dcr.json
az rest --method put --url $dcrUrl --body '@dcr.json' --output none
Remove-Item dcr.json

$dcrImmutableId    = az rest --method get --url $dcrUrl --query properties.immutableId -o tsv
$ingestionEndpoint = az rest --method get --url $dcrUrl --query properties.endpoints.logsIngestion -o tsv

az role assignment create --assignee-object-id $idPrincipalId --assignee-principal-type ServicePrincipal `
  --role 'Monitoring Metrics Publisher' --scope $dcrId --output none
```

---

## 9. Function App Flex Consumption

### 9.1 Creazione

Portale > **Create a resource** > **Function App** > **Create** > **Flex Consumption** > **Select**:

| Scheda | Impostazione | Valore |
| --- | --- | --- |
| Basics | Resource group / Region | Applicativi |
| Basics | Function App name | ad esempio `func-ghas-prod` |
| Basics | Runtime stack / Version | **.NET** / **10 (isolated worker model)** |
| Basics | Instance size | **2048 MB** |
| Storage | Storage account | storage account del passaggio 4 |
| Networking | Enable public access | **On** (distribuzione pubblica) |
| Monitoring | Enable Application Insights | Sì, seleziona la risorsa del passaggio 5 |
| Authentication (se presente) | Host storage / Deployment storage | **Managed identity** > identità assegnata dall'utente del passaggio 3 |
| Authentication (se presente) | Application Insights | **Connection string**/**Secrets**, come nel modello Bicep. Se scegli l'identità gestita, mantieni l'impostazione `APPLICATIONINSIGHTS_AUTHENTICATION_STRING` creata dal wizard e verifica che l'identità abbia **Monitoring Metrics Publisher** su Application Insights |
| Deployment | Continuous deployment | Disabilitato |

**Review + create** > **Create**.

> Se il wizard propone di creare un nuovo storage account o una nuova istanza di Application Insights, seleziona quelli già creati.

### 9.2 Identità gestita

Function App > **Settings** > **Identity** > **User assigned** > **+ Add** > identità del passaggio 3 > **Add**.

### 9.3 Archiviazione dei pacchetti di distribuzione

Function App > **Settings** > **Deployment settings**:

1. **Application package location**: storage account del passaggio 4, contenitore `function-packages`.
2. **Storage authentication**: **User assigned identity** > identità del passaggio 3.
3. **Save**.

### 9.4 Scalabilità

Function App > **Settings** > **Scale and concurrency**: **Maximum instance count** `40`; **Instance memory** `2048 MB`; **Save**.

### 9.5 Variabili d'ambiente

Function App > **Settings** > **Environment variables** > **App settings**. Aggiungi o aggiorna i valori seguenti, quindi **Apply** > **Confirm**:

| Nome | Valore |
| --- | --- |
| `AzureWebJobsStorage__accountName` | `<nome storage account>` |
| `AzureWebJobsStorage__credential` | `managedidentity` |
| `AzureWebJobsStorage__clientId` | `<client ID identità>` |
| `AzureCredentialMode` | `ManagedIdentity` |
| `ManagedIdentityClientId` | `<client ID identità>` |
| `QueueName` | `ghas` |
| `ServiceBusConnection__fullyQualifiedNamespace` | `<namespace>.servicebus.windows.net` |
| `ServiceBusConnection__credential` | `managedidentity` |
| `ServiceBusConnection__clientId` | `<client ID identità>` |
| `LogsIngestion__Endpoint` | `<URI Logs Ingestion della DCE>` |
| `LogsIngestion__DcrImmutableId` | `<immutableId della DCR>` |
| `LogsIngestion__StreamName` | `Custom-GHASAlerts_CL` (o il nome letto nel passaggio 8.3) |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Valore già impostato dal wizard (da Application Insights > **Overview** > **Connection String**) |
| `Privacy__IncludeLocations` | `false` |
| `Privacy__IncludeRawEvent` | `false` |

Rimuovi quindi, se presenti, le impostazioni basate su chiave:

- `AzureWebJobsStorage` (stringa di connessione);
- `DEPLOYMENT_STORAGE_CONNECTION_STRING`.

> Non aggiungere `FUNCTIONS_WORKER_RUNTIME`, `FUNCTIONS_EXTENSION_VERSION` o `WEBSITE_RUN_FROM_PACKAGE`: in Flex Consumption runtime e versione sono configurati dalla piattaforma e il pacchetto viene letto dal contenitore di distribuzione.

### 9.6 Disabilitazione dell'accesso con chiave allo storage

Dopo aver salvato le impostazioni e verificato che la Function App si riavvii senza errori:

1. Storage account > **Settings** > **Configuration**.
2. **Allow storage account key access**: **Disabled** > **Save**.

### 9.7 Impostazioni di sicurezza generali

Function App > **Settings** > **Configuration** > **General settings**: **HTTPS Only** attivato e **Minimum Inbound TLS Version** `1.2` > **Save**.


### Alternativa con Azure CLI

Il piano Flex Consumption viene creato automaticamente da `--flexconsumption-location`.

```powershell
az functionapp create -g $rg -n $func --flexconsumption-location $location `
  --runtime dotnet-isolated --runtime-version 10 --instance-memory 2048 --maximum-instance-count 40 `
  --storage-account $st --app-insights $appi --assign-identity $idId --https-only true `
  --deployment-storage-name $st --deployment-storage-container-name function-packages `
  --deployment-storage-auth-type UserAssignedIdentity --deployment-storage-auth-value $idId

az functionapp config appsettings set -g $rg -n $func --output none --settings `
  "AzureWebJobsStorage__accountName=$st" `
  'AzureWebJobsStorage__credential=managedidentity' `
  "AzureWebJobsStorage__clientId=$idClientId" `
  'AzureCredentialMode=ManagedIdentity' `
  "ManagedIdentityClientId=$idClientId" `
  "QueueName=$queue" `
  "ServiceBusConnection__fullyQualifiedNamespace=$sb.servicebus.windows.net" `
  'ServiceBusConnection__credential=managedidentity' `
  "ServiceBusConnection__clientId=$idClientId" `
  "LogsIngestion__Endpoint=$ingestionEndpoint" `
  "LogsIngestion__DcrImmutableId=$dcrImmutableId" `
  "LogsIngestion__StreamName=$stream" `
  'Privacy__IncludeLocations=false' `
  'Privacy__IncludeRawEvent=false'

# Rimuove le impostazioni basate su chiave (gli errori per impostazioni assenti sono innocui)
az functionapp config appsettings delete -g $rg -n $func `
  --setting-names AzureWebJobsStorage DEPLOYMENT_STORAGE_CONNECTION_STRING --output none

az functionapp config set -g $rg -n $func --min-tls-version 1.2 --output none

# 9.6: dopo aver verificato che l'host si avvii senza errori
az storage account update -g $rg -n $st --allow-shared-key-access false --output none
```

`APPLICATIONINSIGHTS_CONNECTION_STRING` viene impostata da `--app-insights`. Per modificare la scalabilità in seguito: `az functionapp scale config set -g $rg -n $func --maximum-instance-count 40 --instance-memory 2048`.

---

## 10. Pubblicazione del codice della Function

Il progetto è `src/Ghas.Sentinel.Function`. Il codice C# compilato non può essere modificato o pubblicato dall'editor del portale.

### Opzione A: Visual Studio Code

1. Apri la cartella del repository in VS Code e accedi ad Azure dall'estensione **Azure Resources**.
2. Visualizza **Command Palette** > **Azure Functions: Deploy to Function App...**.
3. Seleziona il progetto `src/Ghas.Sentinel.Function`, la sottoscrizione e la Function App del passaggio 9.
4. Conferma la distribuzione e attendi il messaggio di completamento.

### Opzione B: Visual Studio

1. Fai clic destro sul progetto `Ghas.Sentinel.Function` > **Publish**.
2. **Azure** > **Azure Function App (Linux)** > seleziona la Function App esistente.
3. **Finish** > **Publish**.

### Opzione C: Azure CLI (zip deploy)

Richiede .NET SDK 10 e Azure CLI aggiornata. L'utente deve avere almeno **Website Contributor** sulla Function App.

```powershell
az login
az account set --subscription <subscription-id>

dotnet publish src\Ghas.Sentinel.Function\Ghas_Sentinel_Function.csproj -c Release -o .\publish
Compress-Archive -Path .\publish\* -DestinationPath .\function.zip -Force

az functionapp deployment source config-zip `
  --resource-group <rg> `
  --name <function-app> `
  --src .\function.zip
```

Note:

- Lo zip deve contenere il **contenuto** della cartella `publish` (incluso `host.json` alla radice), non la cartella stessa.
- Su Flex Consumption il pacchetto viene caricato nel contenitore `function-packages` configurato in **Deployment settings** con l'identità gestita, quindi funziona anche con l'accesso tramite chiave condivisa disabilitato.
- In alternativa, con Azure Functions Core Tools: `func azure functionapp publish <function-app>` eseguito da `src\Ghas.Sentinel.Function`.
- Se la Function App ha l'accesso pubblico disabilitato (§15), esegui il comando da una rete con accesso all'endpoint privato `scm`.

### Verifica

Function App > **Overview** > scheda **Functions**: deve essere presente la funzione attivata dalla coda Service Bus. In **Monitoring** > **Log stream** non devono comparire errori di avvio o autorizzazione.


### Alternativa con Azure CLI

Per la pubblicazione usa l'[opzione C](#opzione-c-azure-cli-zip-deploy). Per verificare la funzione:

```powershell
az functionapp function list -g $rg -n $func --query '[].name' -o tsv
```

---

## 11. Workbook Sentinel

1. Apri Microsoft Sentinel (portale Azure oppure portale Microsoft Defender) > workspace Sentinel > **Threat management** > **Workbooks** > **+ Add workbook**.
2. Seleziona **Edit** > icona **Advanced Editor** (`</>`) > **Gallery Template**.
3. Sostituisci tutto il contenuto con quello di [`sentinel/ghas-workbook.json`](sentinel/ghas-workbook.json) > **Apply**.
4. **Done editing** > **Save** (icona disco):
   - **Title**: `GitHub Advanced Security alerts`;
   - sottoscrizione e gruppo di risorse del workspace;
   - **Location**: area del workspace.
5. **Apply**.


### Alternativa con Azure CLI

Riusa lo stesso GUID per aggiornare il workbook senza crearne un duplicato.

```powershell
$workbookName = [guid]::NewGuid().Guid
$workbookUrl = "https://management.azure.com/subscriptions/$wsSub/resourceGroups/$wsRg/providers/Microsoft.Insights/workbooks/${workbookName}?api-version=2022-04-01"
@{
  location   = $wsLocation
  kind       = 'shared'
  properties = @{
    displayName    = 'GitHub Advanced Security alerts'
    description    = 'GHAS alert triage with optional ingestion and queue health panels.'
    category       = 'sentinel'
    serializedData = Get-Content sentinel/ghas-workbook.json -Raw
    sourceId       = $wsId
    version        = '1.0'
  }
} | ConvertTo-Json -Depth 5 | Set-Content workbook.json
az rest --method put --url $workbookUrl --body '@workbook.json' --output none
Remove-Item workbook.json
```

---

## 12. Regola di analisi Sentinel (facoltativa)

Crea un incidente quando viene creato o importato un alert di tipo *secret* ancora attivo.

1. Microsoft Sentinel > **Configuration** > **Analytics** > **+ Create** > **Scheduled query rule**.
2. **General**:

   | Impostazione | Valore |
   | --- | --- |
   | Name | `GHAS active secret alert` |
   | Description | `Creates a Sentinel incident when GHAS reports a newly created or backfilled active secret alert.` |
   | Tactics and techniques | **Credential Access** > **T1552** |
   | Severity | High |
   | Status | Enabled |

3. **Set rule logic**:
   - **Rule query**: incolla il contenuto di [`sentinel/analytics-rule.kql`](sentinel/analytics-rule.kql);
   - **Run query every**: `1` ora; **Lookup data from the last**: `1` ora;
   - **Generate alert when number of query results**: **Is greater than** `0`;
   - **Event grouping**: **Trigger an alert for each event**;
   - **Suppression**: Off.
4. **Incident settings**: **Create incidents from alerts triggered by this analytics rule**: Enabled; **Alert grouping**: Disabled.
5. **Automated response**: nessuna, salvo requisiti specifici.
6. **Review + create** > **Save**.


### Alternativa con Azure CLI

Riusa lo stesso GUID per aggiornare la regola senza crearne un duplicato.

```powershell
$ruleName = [guid]::NewGuid().Guid
$ruleUrl = "https://management.azure.com${wsId}/providers/Microsoft.SecurityInsights/alertRules/${ruleName}?api-version=2023-02-01"
@{
  kind       = 'Scheduled'
  properties = @{
    displayName           = 'GHAS active secret alert'
    description           = 'Creates a Sentinel incident when GHAS reports a newly created or backfilled active secret alert.'
    severity              = 'High'
    enabled               = $true
    query                 = Get-Content sentinel/analytics-rule.kql -Raw
    queryFrequency        = 'PT1H'
    queryPeriod           = 'PT1H'
    triggerOperator       = 'GreaterThan'
    triggerThreshold      = 0
    suppressionEnabled    = $false
    suppressionDuration   = 'PT5H'
    tactics               = @('CredentialAccess')
    techniques            = @('T1552')
    incidentConfiguration = @{ createIncident = $true }
    eventGroupingSettings = @{ aggregationKind = 'AlertPerResult' }
  }
} | ConvertTo-Json -Depth 5 | Set-Content rule.json
az rest --method put --url $ruleUrl --body '@rule.json' --output none
Remove-Item rule.json
```

---

## 13. Service hook Azure DevOps

Crea **tre sottoscrizioni** per ciascun progetto, una per ogni evento Advanced Security.

| Evento nella UI | Event ID |
| --- | --- |
| Advanced security alert created | `ms.vss-alerts.alert-created-event` |
| Advanced security alert state changed | `ms.vss-alerts.alert-state-changed-event` |
| Advanced security alert updated | `ms.vss-alerts.alert-updated-event` |

### 13.1 Facoltativo: service connection invece della SAS

Se non vuoi usare una chiave SAS:

1. Azure DevOps > **Project settings** > **Service connections** > **New service connection** > **Azure Resource Manager** > **Workload identity federation (automatic)** oppure **(manual)**.
2. Completa la creazione e annota il service principal associato (**Manage App registration**/**Manage service connection roles**).
3. Nel portale Azure, sulla coda `ghas` > **Access control (IAM)** > assegna **Azure Service Bus Data Sender** al service principal.

### 13.2 Creazione delle sottoscrizioni

Per ciascuno dei tre eventi:

1. Azure DevOps > progetto > **Project settings** > **General** > **Service hooks** > **+ Create subscription**.
2. Servizio: **Azure Service Bus** > **Next**.
3. **Trigger**: seleziona l'evento. Filtri **Repository**, **Branch**, **Alert type**, **Severity** e **State**: lascia **[Any]**, salvo esigenze specifiche > **Next**.
4. **Action**: **Send a message to a Service Bus Queue**.
5. Autenticazione:
   - **SAS**: incolla la stringa di connessione del criterio `sendOnly` **senza** `;EntityPath=ghas`;
   - **Service connection**: seleziona la service connection del passaggio 13.1 e inserisci l'host `sb://<namespace>.servicebus.windows.net`.
6. **Queue name**: `ghas`.
7. Seleziona **Send as non-serialized string** (obbligatorio: la Function si aspetta JSON non serializzato da .NET).
8. Lascia i valori predefiniti per i dettagli della risorsa e dei messaggi.
9. **Finish**. Evita **Test** in produzione: un payload di test non valido viene ritentato e può finire nella coda dei messaggi non recapitabili.

> Non creare sottoscrizioni duplicate per lo stesso evento e la stessa coda, altrimenti in Sentinel arriveranno eventi duplicati.


### Alternativa con Azure CLI

Lo script `scripts/New-GhasServiceHooks.ps1` crea le tre sottoscrizioni con **Send as non-serialized string** (`bypassSerializer`) e non sovrascrive quelle esistenti. Richiede un PAT con permessi di gestione dei service hook nella variabile `AZDO_ACCESS_TOKEN`.

```powershell
$env:AZDO_ACCESS_TOKEN = Read-Host 'PAT Azure DevOps' -MaskInput

# Modalità SAS (facoltativamente salva la stringa nel Key Vault)
.\scripts\New-GhasServiceHooks.ps1 -OrganizationUrl 'https://dev.azure.com/<organizzazione>' `
  -ProjectId '<id-progetto>' -NamespaceName $sb -QueueName $queue `
  -ResourceGroup $rg -AuthenticationMode Sas -KeyVaultName $kv

Remove-Item Env:AZDO_ACCESS_TOKEN
```

Per la modalità con service connection (13.1), crea la service connection dalla UI di Azure DevOps, assegna il ruolo al suo service principal e avvia lo script con `-AuthenticationMode ServiceConnection -ServiceConnectionId '<id-service-connection>'`:

```powershell
az role assignment create --assignee '<app-id-service-principal>' `
  --role 'Azure Service Bus Data Sender' --scope $queueId --output none
```

Ripeti lo script per ogni progetto Azure DevOps.

---

## 14. Verifica end-to-end

1. Genera o modifica un alert Advanced Security di prova (ad esempio, cambia lo stato di un alert esistente non critico).
2. Azure DevOps > **Service hooks** > colonna **State**/**History** della sottoscrizione: l'ultima consegna deve risultare **Succeeded**.
3. Service Bus > coda `ghas` > **Overview**: i messaggi attivi tornano a `0` e i **Dead-letter messages** restano a `0`.
4. Function App > funzione > **Invocations** oppure Application Insights > **Transaction search**: esecuzione riuscita.
5. Workspace Sentinel > **Logs**:

   ```kusto
   GHASAlerts_CL
   | where TimeGenerated > ago(1h)
   | summarize arg_max(TimeGenerated, *) by EventId
   | project TimeGenerated, EventAction, AlertType, Severity, State, RepositoryName, Title
   ```

   Il primo inserimento può richiedere alcuni minuti.
6. Apri il workbook **GitHub Advanced Security alerts** e verifica i dati.

### Problemi comuni

| Sintomo | Verifica |
| --- | --- |
| Service hook in errore `401`/`403` | Stringa SAS senza `EntityPath`, criterio con diritto **Send**, oppure ruolo **Data Sender** della service connection |
| Messaggi fermi in coda | Funzione pubblicata, impostazioni `ServiceBusConnection__*`, ruolo **Data Receiver** dell'identità |
| Errori `403` dalla Logs Ingestion API | Ruolo **Monitoring Metrics Publisher** sulla DCR e tempo di propagazione |
| Errori `404`/stream non trovato | `LogsIngestion__DcrImmutableId`, `LogsIngestion__StreamName` ed endpoint della DCE |
| Avvio host fallito | Ruoli sullo storage e impostazioni `AzureWebJobsStorage__*` |
| Messaggi in dead-letter | Application Insights > **Failures** per il motivo; correggi la causa e reinvia i messaggi |

### 14.1 Test HTTP: invio di un messaggio simulando il service hook

Puoi verificare la catena Service Bus > Function > Sentinel senza generare un alert reale. Invia alla coda, tramite l'API REST di Service Bus, lo stesso payload JSON che spedirebbe il service hook. Il record di test contiene dati fittizi: puoi riconoscerlo dal titolo `TEST - ...`.

Richiede le variabili `$rg`, `$sb` e `$queue` delle sezioni precedenti. Per l'autenticazione hai due possibilità:

- **SAS**: chiave del criterio `sendOnly` (§6.3);
- **Entra ID**: il tuo utente deve avere **Azure Service Bus Data Sender** sulla coda.

```powershell
$eventId = "manual-test-$([guid]::NewGuid())"
$alertId = Get-Random -Minimum 900000 -Maximum 999999
$body = @{
  id                 = $eventId
  eventType          = 'ms.vss-alerts.alert-created-event'
  createdDate        = (Get-Date).ToUniversalTime().ToString('o')
  resourceContainers = @{
    account = @{ baseUrl = 'https://dev.azure.com/contoso' }
    project = @{ id = '00000000-0000-0000-0000-000000000001' }
  }
  resource           = @{
    alertId       = $alertId
    alertType     = 'secret'
    severity      = 'high'
    state         = 'active'
    title         = 'TEST - simulated secret scanning alert'
    repositoryUrl = 'https://dev.azure.com/contoso/Security/_git/app'
    gitRef        = 'refs/heads/main'
    tools         = @(@{ name = 'secret-scanner'; rules = @(@{ opaqueId = 'test-rule'; friendlyName = 'Test rule' }) })
  }
} | ConvertTo-Json -Depth 10

$uri = "https://$sb.servicebus.windows.net/$queue/messages"

# Opzione 1: token SAS dal criterio sendOnly
$key = az servicebus queue authorization-rule keys list -g $rg --namespace-name $sb `
  --queue-name $queue -n sendOnly --query primaryKey -o tsv
$resource = [uri]::EscapeDataString("https://$sb.servicebus.windows.net/$queue".ToLowerInvariant())
$expiry = [DateTimeOffset]::UtcNow.AddMinutes(10).ToUnixTimeSeconds()
$hmac = [System.Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($key))
$signature = [uri]::EscapeDataString([Convert]::ToBase64String(
  $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes("$resource`n$expiry"))))
$auth = "SharedAccessSignature sr=$resource&sig=$signature&se=$expiry&skn=sendOnly"

# Opzione 2: token Entra ID (sostituisce l'opzione 1)
# $auth = "Bearer $(az account get-access-token --resource https://servicebus.azure.net --query accessToken -o tsv)"

Invoke-RestMethod -Method Post -Uri $uri -Body $body -Headers @{
  Authorization    = $auth
  BrokerProperties = (@{ MessageId = $eventId } | ConvertTo-Json -Compress)
} -ContentType 'application/json'
```

La risposta `201 Created` non restituisce contenuto. Se `Invoke-RestMethod` non mostra errori, il messaggio è stato accodato.

- **`MessageId` univoco:** la coda ha il rilevamento dei duplicati attivo per 10 minuti, quindi rieseguendo lo script con lo stesso `MessageId` il messaggio verrebbe scartato. Lo script ne genera uno nuovo a ogni esecuzione.
- **Altri eventi:** per simulare un cambio di stato, usa `eventType = 'ms.vss-alerts.alert-state-changed-event'` e `state = 'dismissed'` (o `fixed`) con lo stesso `alertId`.
- **File `.http`:** in alternativa allo script usa [`tests/http/send-test-alert.http`](tests/http/send-test-alert.http) con l'estensione VS Code **REST Client** o con Visual Studio. Imposta `@namespace` e `@authorization` (il valore di `$auth` dello script, oppure `Bearer <token>`), quindi esegui **Send Request** su "Alert created" e, se vuoi, su "Alert state changed". `MessageId`, `id` e data vengono generati a ogni invio.

Dopo alcuni minuti controlla il risultato:

```kusto
GHASAlerts_CL
| where Title startswith "TEST - "
| project TimeGenerated, EventId, EventAction, AlertId, Severity, State, RepositoryName
```

Se il messaggio finisce in dead-letter, consulta la tabella **Problemi comuni** qui sopra. A test concluso, i record fittizi restano nella tabella fino alla scadenza della retention; filtrali con `Title !startswith "TEST - "` nelle query, se necessario.

> In modalità privata (§15) la chiamata deve partire da una rete che raggiunge l'endpoint privato di Service Bus, a meno che non sia attivo `allowPublicServiceBusAccess`.

Per l'importazione iniziale degli alert attivi già esistenti vedi la sezione **Backfill active alerts** del [README](README.md#backfill-active-alerts): richiede l'esecuzione di un'utilità .NET e non è disponibile solo tramite interfaccia grafica.


### Alternativa con Azure CLI

```powershell
# Messaggi attivi e dead-letter
az servicebus queue show -g $rg --namespace-name $sb -n $queue --query countDetails

# Dati in Sentinel (richiede l'estensione log-analytics)
$wsCustomerId = az monitor log-analytics workspace show --subscription $wsSub -g $wsRg -n $wsName --query customerId -o tsv
az monitor log-analytics query -w $wsCustomerId -o table --analytics-query `
  'GHASAlerts_CL | where TimeGenerated > ago(1h) | summarize arg_max(TimeGenerated, *) by EventId | project TimeGenerated, EventAction, AlertType, Severity, State, RepositoryName, Title'
```

---

## 15. Rete privata hub & spoke (facoltativa)

Applica questa sezione solo se l'hub & spoke esiste già (VNet, subnet, zone DNS private, collegamenti DNS e Azure Monitor Private Link Scope). Leggi prima i requisiti nel [README](README.md#optional-private-hub--spoke-integration). Esegui la pubblicazione del codice da un host connesso alla rete privata.

### 15.1 Differenze rispetto alla distribuzione pubblica

| Risorsa | Modifica |
| --- | --- |
| Service Bus | Tier **Premium**, 1 messaging unit, da scegliere alla creazione (non si può passare da Standard a Premium) |
| Key Vault | **Purge protection** abilitata |
| Storage, Service Bus, Key Vault | **Networking** > **Public network access**: Disabled (per Service Bus solo se non serve l'eccezione per i service hook) |
| Application Insights | **Network Isolation**: ingestione e query pubbliche disabilitate |
| DCE | **Network Isolation** > accesso pubblico disabilitato |

### 15.2 Endpoint privati

Per ogni risorsa: **Networking** > **Private endpoint connections** > **+ Private endpoint**, subnet degli endpoint privati, integrazione con la **zona DNS privata esistente**.

| Risorsa | Sub-resource | Zona DNS privata |
| --- | --- | --- |
| Storage | `blob` | `privatelink.blob.core.windows.net` |
| Storage | `queue` | `privatelink.queue.core.windows.net` |
| Storage | `table` | `privatelink.table.core.windows.net` |
| Service Bus | `namespace` | `privatelink.servicebus.windows.net` |
| Key Vault | `vault` | `privatelink.vaultcore.azure.net` |
| Function App | `sites` | `privatelink.azurewebsites.net` |

### 15.3 Function App

1. **Settings** > **Networking** > **Outbound traffic configuration** > **Virtual network integration** > **Add virtual network integration** > subnet di integrazione delegata a `Microsoft.App/environments` > **Connect**.
2. **Networking** > **Inbound traffic configuration** > **Public network access**: Disabled, dopo aver creato l'endpoint privato `sites`.

### 15.4 Azure Monitor Private Link Scope

AMPLS esistente > **Configure** > **Azure Monitor Resources** > **+ Add** > aggiungi la **DCE** e **Application Insights**. Il workspace Sentinel deve essere già collegato all'AMPLS. Non modificare le impostazioni di rete condivise del workspace senza valutare l'impatto sugli altri utilizzatori.

### 15.5 Service hook

I service hook di Azure DevOps Services **non possono raggiungere un Service Bus raggiungibile solo privatamente**. Se servono i service hook diretti, lascia abilitato l'accesso pubblico **solo** sul namespace Service Bus. Questa è un'eccezione ibrida, non una distribuzione completamente privata.


### Alternativa con Azure CLI

Applica le varianti seguenti **al posto** dei comandi corrispondenti, rispettando quest'ordine: risorse dati → endpoint privati dei dati → DCE e AMPLS → Function App → endpoint privato `sites`.

```powershell
$peSubnetId   = '<id-subnet-endpoint-privati>'
$funcSubnetId = '<id-subnet-integrazione-delegata-a-Microsoft.App/environments>'
$amplsId      = '<id-AMPLS>'
$zones = @{
  blob = '<id-zona-privatelink.blob.core.windows.net>'
  queue = '<id-zona-privatelink.queue.core.windows.net>'
  table = '<id-zona-privatelink.table.core.windows.net>'
  namespace = '<id-zona-privatelink.servicebus.windows.net>'
  vault = '<id-zona-privatelink.vaultcore.azure.net>'
  sites = '<id-zona-privatelink.azurewebsites.net>'
}
```

Variazioni nei comandi di creazione:

| Passaggio | Parametri da usare |
| --- | --- |
| 4. Storage | `--public-network-access Disabled --default-action Deny --bypass None` |
| 5. Application Insights | aggiungi `--ingestion-access Disabled --query-access Disabled` |
| 6. Service Bus | `--sku Premium --capacity 1 --public-network-access Disabled` (`Enabled` solo per l'eccezione dei service hook, vedi 15.5) |
| 7. Key Vault | aggiungi `--enable-purge-protection true`; usa `--public-network-access Disabled --default-action Deny` |
| 9. Function App | aggiungi `--subnet $funcSubnetId` ad `az functionapp create` |

Endpoint privati di storage, Service Bus e Key Vault:

```powershell
function New-GhasPrivateEndpoint($name, $targetId, $groupId) {
  az network private-endpoint create -g $rg -n $name -l $location --subnet $peSubnetId `
    --private-connection-resource-id $targetId --group-id $groupId --connection-name $name --output none
  az network private-endpoint dns-zone-group create -g $rg --endpoint-name $name -n default `
    --private-dns-zone $zones[$groupId] --zone-name $groupId --output none
}

New-GhasPrivateEndpoint 'pe-storage-blob'  $stId 'blob'
New-GhasPrivateEndpoint 'pe-storage-queue' $stId 'queue'
New-GhasPrivateEndpoint 'pe-storage-table' $stId 'table'
New-GhasPrivateEndpoint 'pe-servicebus'    $sbId 'namespace'
New-GhasPrivateEndpoint 'pe-keyvault'      $kvId 'vault'
```

DCE privata (da creare prima della DCR del passaggio 8) e collegamento all'AMPLS:

```powershell
$dceId  = "/subscriptions/$wsSub/resourceGroups/$wsRg/providers/Microsoft.Insights/dataCollectionEndpoints/dce-ghas-prod"
$dceUrl = "https://management.azure.com${dceId}?api-version=2023-03-11"
@{ location = $wsLocation; properties = @{ networkAcls = @{ publicNetworkAccess = 'Disabled' } } } |
  ConvertTo-Json -Depth 5 | Set-Content dce.json
az rest --method put --url $dceUrl --body '@dce.json' --output none
Remove-Item dce.json

$amplsParts = $amplsId -split '/'
$appiId = az monitor app-insights component show -g $rg --app $appi --query id -o tsv
az monitor private-link-scope scoped-resource create --subscription $amplsParts[2] -g $amplsParts[4] `
  --scope-name $amplsParts[8] -n ghas-dce --linked-resource $dceId --output none
az monitor private-link-scope scoped-resource create --subscription $amplsParts[2] -g $amplsParts[4] `
  --scope-name $amplsParts[8] -n ghas-appi --linked-resource $appiId --output none
```

Nel passaggio 8 aggiungi `dataCollectionEndpointId = $dceId` all'interno di `properties` della DCR. Leggi poi l'endpoint dalla DCE, non dalla DCR:

```powershell
$ingestionEndpoint = az rest --method get --url $dceUrl --query properties.logsIngestion.endpoint -o tsv
```

Dopo il passaggio 9, crea l'endpoint privato della Function App e disabilita l'accesso pubblico:

```powershell
$funcId = az functionapp show -g $rg -n $func --query id -o tsv
New-GhasPrivateEndpoint 'pe-function' $funcId 'sites'
az resource update --ids $funcId --set properties.publicNetworkAccess=Disabled --output none
```

---

## 16. Riepilogo delle assegnazioni di ruolo

| Identità | Ruolo | Ambito |
| --- | --- | --- |
| Identità gestita Function | Storage Blob Data Owner | Storage account |
| Identità gestita Function | Storage Blob Data Contributor | Storage account |
| Identità gestita Function | Storage Queue Data Contributor | Storage account |
| Identità gestita Function | Storage Table Data Contributor | Storage account |
| Identità gestita Function | Azure Service Bus Data Receiver | Coda `ghas` |
| Identità gestita Function | Monitoring Metrics Publisher | DCR |
| Service principal della service connection (facoltativo) | Azure Service Bus Data Sender | Coda `ghas` |
| Utente o identità del backfill (facoltativo) | Azure Service Bus Data Sender | Coda `ghas` |
| Operatore che salva segreti (facoltativo) | Key Vault Secrets Officer | Key Vault |
