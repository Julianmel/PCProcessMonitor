# Invariantes Técnicas do Windows PowerShell

Diretrizes essenciais de estabilidade, codificação e interoperabilidade para scripts e comandos PowerShell no ambiente Windows:

## 1. Obrigatoriedade de UTF-8 com BOM
- Todo script `.ps1` criado ou editado, e todo arquivo de log gerado no Windows DEVE ser gravado com codificação **UTF-8 com BOM** (`[System.Text.UTF8Encoding]::new($true)`).
- **Motivo:** O Windows PowerShell 5.1 lê scripts `.ps1` sem BOM utilizando a página de código ANSI padrão (Windows-1252), o que corrompe caracteres acentuados (*mojibake*) e quebra a interpretação de strings literais.

## 2. Automação COM do Outlook Segura (Filtros .Restrict)
- Ao interagir com o Outlook via objeto COM `Outlook.Application`, nunca varrer toda a coleção de itens com loops abertos `foreach ($item in $folder.Items)`.
- É **obrigatório** aplicar filtros restritivos com `.Restrict(...)` (ex: por intervalo de datas):
  ```powershell
  $items = $calendar.Items.Restrict("[Start] >= '2026-09-30 00:00' AND [Start] <= '2026-09-30 23:59'")
  ```
- **Motivo:** Coleções com milhares de compromissos históricos congelam ou causam timeouts na interface COM do Outlook.

## 3. Proteção contra Interpolação no CLI
- Ao invocar comandos do PowerShell (`powershell.exe` ou `pwsh`) passando script blocks na linha de comando que contenham variáveis (`$var`, `$_`), proteger o bloco sempre com **aspas simples** `'...'`.
- **Motivo:** Aspas duplas `"..."` fazem com que o shell pai interpole prematuramente as variáveis locais antes de passá-las ao processo filho, resultando em strings vazias e erros de sintaxe.
