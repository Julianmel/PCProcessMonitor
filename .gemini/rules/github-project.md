# Regra de Governança do GitHub Projects (Kanban, Campos e Ciclo de Vida)

Esta regra é obrigatória para a criação e manutenção de projetos no GitHub e gestão de issues:

## 1. Estrutura Padrão para Novos Projetos
1. **Modelo Kanban:** Todo projeto criado no GitHub Projects DEVE utilizar a feature estilo KANBAN.
2. **Campos Customizados Obrigatórios:**
   - `Start Time`: Texto (formato `HH:MM`) para registrar a hora de início.
   - `End Time`: Texto (formato `HH:MM`) para registrar a hora de fim.
   - `Total Time`: Texto (ex: `20 min`, `45 min`) para registrar a duração real da execução.
3. **View Principal Obrigatória:**
   O projeto deve ter uma view principal configurada com as colunas exatamente nesta ordem:
   ```
   1. Title
   2. Assignees
   3. Status
   4. Start Date
   5. Start Time
   6. End Date
   7. End Time
   8. Total Time
   9. Closed
   ```

## 2. Ciclo de Vida da Tarefa

### Ao Iniciar a Atividade (Start):
- Preencher o campo **Start Date** com a data atual (`AAAA-MM-DD`).
- Preencher o campo **Start Time** com o horário de início (`HH:MM`).
- **MUDANÇA IMEDIATA DE STATUS:** Alterar o status da issue no projeto para **`In progress`** (`PVTSSF_...` -> Option `In progress`).
- **REABASTECIMENTO AUTOMÁTICO DA FILA ("Ready"):** Imediatamente após mover a issue para `In progress`, identificar a próxima issue prioritária em **`Backlog`** e movê-la para o status **`Ready`** (Option `Ready`), deixando-a preparada como a próxima da esteira a ser executada.

### Ao Concluir a Atividade (Done):
- Preencher **End Date** com a data de conclusão.
- Preencher **End Time** com o horário de término.
- Preencher **Total Time** com o tempo total real decorrido da atividade (não precisa ser múltiplo de 10 min no GitHub).
- **MUDANÇA DE STATUS:** Alterar o status para **`Done`**.
- Inserir comentário técnico detalhado na issue relatando as alterações, testes e commits realizados.
- Fechar a issue como concluída (`gh issue close <N> --reason "completed"`).
