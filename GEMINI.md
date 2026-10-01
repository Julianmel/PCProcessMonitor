# Diretrizes Globais do Projeto (Antigravity Rules)

Este repositório adota as regras de governança de projetos, automação de calendário e salvaguardas técnicas do Windows PowerShell definidas a seguir.

---

## 1. Governança do GitHub Projects & Gestão de Issues
* **Padrão Obrigatório de Novos Projetos:** Todo projeto criado no GitHub Projects DEVE utilizar a feature estilo **KANBAN**.
* **Campos Customizados Obrigatórios:** Incluir no projeto os campos:
  * `Start Time` (Hora de início da issue)
  * `End Time` (Hora de fim da issue)
  * `Total Time` (Tempo total decorrido da issue)
* **View Principal do Projeto:** O projeto deve conter uma visualização principal com as colunas rigorosamente nesta ordem:
  1. `Title`
  2. `Assignees`
  3. `Status`
  4. `Start Date`
  5. `Start Time`
  6. `End Date`
  7. `End Time`
  8. `Total Time`
  9. `Closed`
* **Transição Automática para "In progress":** Sempre que for atribuída a data e hora de início (`Start Date` / `Start Time`), alterar **IMEDIATAMENTE** o status da issue no projeto para **`In progress`**.
* **Reabastecimento Automático da Fila ("Ready"):** Sempre que uma issue for movida para **`In progress`**, identificar imediatamente a próxima issue prioritária em **`Backlog`** e movê-la para o status **`Ready`**, sinalizando que será a próxima a ser executada na sequência da esteira.
* **Fechamento em "Done":**
  * Registrar `End Date`, `End Time` e o tempo real decorrido em `Total Time` (no GitHub o tempo não necessita ser múltiplo de 10 min).
  * Alterar o status para **`Done`**.
  * Publicar comentário técnico com relatório das alterações e entregáveis.
  * Encerrar a issue no GitHub como concluída.

---

## 2. Automação do Calendário do Outlook (Timesheet)
* **Regra dos 10 Minutos (Exclusiva do Outlook):**
  * Entradas no calendário devem ter duração mínima de 10 minutos e todos os tempos adicionais devem ser estritamente **múltiplos de 10 minutos** (10m, 20m, 30m, 40m, etc.).
  * Tarefas com execução inferior a 10 minutos devem ser agrupadas para caber dentro de um bloco de 10 minutos.
* **Categorias Padronizadas:**
  * O agente DEVE **SEMPRE PERGUNTAR** ao usuário quais categorias aplicar antes de gerar os compromissos, a menos que tenham sido explicitamente indicadas no prompt da demanda.
* **Observações Completas:**
  * Todos os dados, resumos, métricas e entregáveis apresentados pelo agente após o cumprimento de uma tarefa DEVEM ser escritos integralmente no campo **Observações** (Body) do compromisso.
* **Formatação Tipográfica Obrigatória:**
  * O corpo das observações deve ser formatado estritamente na fonte **Courier New tamanho 10 pt**, via automação COM (`$insp.WordEditor`):
    ```powershell
    $appt.Display()
    $doc = $appt.GetInspector.WordEditor
    if ($doc) {
        $doc.Range().Font.Name = "Courier New"
        $doc.Range().Font.Size = 10
    }
    $appt.Save()
    $appt.Close(0) # 0 = olSave
    ```
* **Identificador de Conversa (Rodapé):**
  * Sempre na última anotação de uma sequência ou sobre o tema em questão, o rodapé DEVE conter a identificação da conversa:
    ```text
    ================================================================================
    HISTÓRICO DA CONVERSA (ANTIGRAVITY CLI):
    agy --conversation=<conversation-id>
    ================================================================================
    ```

---

## 3. Invariantes Técnicas do Windows PowerShell
* **Obrigatoriedade de UTF-8 com BOM:**
  * Todos os scripts `.ps1` criados ou modificados, bem como novos arquivos de log gravados no Windows DEVEM utilizar codificação **UTF-8 com BOM** (`[System.Text.UTF8Encoding]::new($true)`), prevenindo erros de sintaxe e corrupção de caracteres acentuados (*mojibake*) no Windows PowerShell 5.1.
* **Filtros Seguros em Automações COM:**
  * Em consultas a pastas volumosas do Outlook (ex: Calendário MAPI), nunca iterar toda a coleção de itens com `foreach`. Utilizar obrigatoriamente `.Restrict("[Start] >= '...' AND [Start] <= '...'")` para evitar travamentos da interface COM.
* **Proteção contra Interpolação Prematura no CLI:**
  * Ao passar blocos de código para `powershell.exe` ou `pwsh` contendo variáveis `$var`, envolver a instrução em aspas simples `'...'` para impedir que o terminal pai substitua variáveis por strings vazias antes da execução.
