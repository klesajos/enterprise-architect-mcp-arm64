# Enterprise Architect MCP — Tahák nástrojů

**Autor:** Josef Klesa (klesajos) · © 2026, MIT

Server: `enterprise-architect` (`MCP3.exe`), spuštěn s `-enableEdit -setTimeout 60`.
Editační nástroje (★) jsou k dispozici jen díky `-enableEdit`. Mazat lze **pouze konektory/zprávy** — před úpravami zálohuj přes baseline.

ID jsou číselná a stabilní: `ElementID`, `DiagramID`, `ConnectorID`, `PackageID`, `AttributeID`, `OperationID`. Většina nástrojů je vyžaduje, takže se obvykle nejdřív hledá/čte.

---

## 📦 Balíčky (Packages)

| Nástroj | Co dělá | Klíčové vstupy |
|---|---|---|
| `get_root_packages` | Kořenový balíček (balíčky) modelu — výchozí bod. | _(žádné)_ |
| `get_current_package` | Aktuálně vybraný balíček v EA. Je-li vybrán element/diagram, vrátí jeho nadřazený balíček. Použij před vytvářením. | _(žádné)_ |
| `get_packages_information` | Detaily zadaných balíčků. | `packageIDs[]` |
| `find_packages_by_name` | Najde balíčky podle názvu v celém modelu. | `name`, `exactMatch` (def. true) |
| ★ `create_or_update_package` | Vytvoří balíček (`packageID:0`) pod rodičem, nebo upraví existující (`packageID:≠0`). | `packageInfo{name, owningPackageID, packageID, description}`, `taggedValues` |
| ★ `clone_package` | Úplná kopie balíčku do téhož rodiče. | `packageID` |
| ★ `create_baseline` | **Snímek/záloha** balíčku. Vrací baseline ID. Udělej před riskantní úpravou. | `packageID` |
| ★ `apply_baseline` | **Vrácení** balíčku do baseline. Diagramy se obnoví automaticky. | `packageID`, `baselineID` |

## 🧩 Elementy (Elements)

| Nástroj | Co dělá | Klíčové vstupy |
|---|---|---|
| `get_current_elements` | Aktuálně vybrané elementy v EA. | _(žádné)_ |
| `get_elements_information` | Plný detail: operace, atributy, podřízené elementy a diagramy. | `elementIDs[]` |
| `find_elements_by_name` | Najde elementy podle názvu v celém modelu. | `name`, `exactMatch` (def. true) |
| `find_element_in_diagrams` | Vypíše všechny diagramy, kde se element vyskytuje. | `elementID` |
| `select_element_in_browser` | Zvýrazní element v okně Browser v EA. | `elementID` |
| `select_element_in_diagram` | Vybere element v diagramu (otevře ho, je-li třeba). | `elementID`, `diagramID` |
| `export_element_linked_documents` | Exportuje navázané dokumenty elementů do RTF (`<elementID>.rtf`). | `elementIDs[]`, `pathToExport` |
| ★ `create_or_update_elements` | Vytvoří (`elementID:0`) nebo upraví (`elementID:≠0`) elementy. Podporuje stereotypy, tagged values a formátování barev/okraje/textu (per-diagram nebo celý model). | `elementInfo[]{name, type, owningPackageID, owningElementID, elementID, stereotypes, taggedValues, elementFormat, ...}` |
| ★ `create_or_update_operations` | Přidá/upraví operace (metody) elementu vč. parametrů, scope, návratového typu, pořadí. | `elementID`, `operationInfo[]` |
| ★ `create_or_update_attributes` | Přidá/upraví atributy elementu (typ, scope, pořadí, stereotyp). | `elementID`, `attributeInfo[]` |
| ★ `clone_elements` | Úplná kopie elementů do téhož rodičovského balíčku. | `elementID[]` |
| ★ `import_element_linked_documents` | Importuje RTF navázané dokumenty na elementy (soubor musí být `<elementID>.rtf`). | `elementID[]`, `pathToImport` |

## 🔗 Konektory a zprávy (Connectors & Messages)

| Nástroj | Co dělá | Klíčové vstupy |
|---|---|---|
| `get_current_connector` | Konektor vybraný v aktuálním diagramu. | _(žádné)_ |
| `get_connectors_information` | Plný detail vč. tagged values. | `connectorIDs[]` |
| ★ `create_or_update_connectors` | Vytvoří (`connectorID:0`) nebo upraví vztahy mezi elementy. Nastav `sourceEnd`/`targetEnd` (relatedElementID, multiplicity, scope, name), styl, barvu/šířku, stereotypy, tagged values. Pak diagram obnov. | `connectorInfo[]{type, sourceEnd, targetEnd, ...}` |
| ★ `create_or_update_messages` | Vytvoří/upraví zprávy mezi lifelinami v **sekvenčním diagramu**. Podporuje async/return, zprávy typované operací, pořadí. | `diagramID`, `messageInfo[]{sourceElementID, targetElementID, order, ...}` |
| ★ `delete_connectors_or_messages` | **Jediný mazací nástroj.** Odstraní konektory/zprávy. Poté diagram obnov. | `connectorIDs[]` |

## 📐 Diagramy (Diagrams)

| Nástroj | Co dělá | Klíčové vstupy |
|---|---|---|
| `get_current_diagram` | Aktivní diagram v EA. | _(žádné)_ |
| `get_opened_diagrams` | Všechny aktuálně otevřené diagramy. | _(žádné)_ |
| `get_diagrams_information` | Detail vč. zobrazených elementů a konektorů. **Pro analýzu diagramu** použij tohle, ne obrázek. | `diagramIDs[]` |
| `get_diagram_image` | PNG render diagramu (jen vizuál, ne pro analýzu). | `diagramID` |
| `open_diagrams` | Otevře diagramy v EA. | `diagramIDs[]` |
| `reload_diagrams` | Obnoví diagramy, aby se zobrazily nové elementy/konektory. | `diagramIDs[]` |
| ★ `create_or_update_diagram` | Vytvoří (`diagramID:0`) nebo upraví diagram, vlastněný balíčkem nebo elementem. Typ nelze po vytvoření změnit. | `diagramInfo{name, type, owningPackageID, owningElementID, diagramID}` |
| ★ `place_elements_on_diagram` | Umístí existující elementy na diagram na x/y se šířkou/výškou. Auto-obnova — ruční reload není třeba. | `diagramID`, `placements[]{elementID, x, y, width, height, style}` |
| ★ `layout_connectors` | Automatické rozmístění konektorů v diagramu. | `diagramID` |
| ★ `change_connector_visibility` | Zobrazí/skryje konkrétní konektory na diagramu. | `diagramID`, `connectorIDs[]`, `showHide` |

---

## Konvence a záludnosti

- **Vytvoření vs. úprava** se řídí ID polem: `0` = nový, nenulové = úprava existujícího. Platí pro elementy, diagramy, balíčky, konektory, operace, atributy i zprávy.
- **`type` je neměnný** po vytvoření u elementů, konektorů i diagramů.
- **Stereotypové/profilové typy** používají plně kvalifikovaný název, např. `Archimate3::ArchiMate_ApplicationComponent`, `Archimate3::Application` (diagram), `Archimate3::ArchiMate_Serving` (konektor).
- **Vlastnictví**: element/diagram patří buď balíčku (`owningPackageID`), NEBO rodičovskému elementu (`owningElementID`, druhé nastav na 0).
- **Obnova po úpravě vztahů**: konektory/zprávy vyžadují `reload_diagrams`; umístění elementů se obnoví samo.
- **Barvy**: RGB 0–255 na kanál; `red:-1` = výchozí barva. `borderWidth`/šířka konektoru: -1..3, -1 = výchozí.
- **Scope** hodnoty: `Private`, `Protected`, `Package`, `Public`.
- **Navázané dokumenty** jsou RTF, název souboru musí být `<elementID>.rtf`.
- **Timeout** je 60 s (`-setTimeout 60`); zvyš až k 600 při náročných operacích (EA tu běží pod x64 emulací).
- **Timeout / „Failed to connect to Enterprise Architect"** téměř vždy znamená **zavřený projekt v EA** (nebo neběžící EA) — nejdřív otevři repozitář, pak opakuj.

## Bezpečný postup úprav
1. `get_current_package` / `find_packages_by_name` → cílové `packageID`.
2. ★ `create_baseline(packageID)` → ulož vrácené baseline ID.
3. Proveď úpravy (vytvoř/uprav elementy, konektory, diagramy…).
4. `reload_diagrams` pro vizuální kontrolu.
5. Když je něco špatně → ★ `apply_baseline(packageID, baselineID)` pro návrat.
