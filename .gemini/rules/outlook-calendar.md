# Regra de Automação do Calendário do Outlook

Esta regra rege todo registro de compromissos e apontamentos de horas gerados no Outlook Calendar via PowerShell / automação COM.

## 1. Duração e Granularidade (Regra dos 10 Minutos)
- **Exclusividade:** A regra de múltiplos de 10 minutos aplica-se exclusivamente aos compromissos do Calendário do Outlook.
- **Mínimo:** Duração mínima de 10 minutos por compromisso.
- **Múltiplos de 10 min:** Todos os tempos devem ser múltiplos de 10 minutos (10m, 20m, 30m, etc.).
- **Agrupamento:** Quando atividades individuais levarem menos de 10 minutos de execução, agrupar o máximo de itens correlatos dentro do mesmo bloco de 10 minutos.

## 2. Categorias
- **Pergunta Obrigatória:** O agente DEVE SEMPRE PERGUNTAR ao usuário quais são as categorias a serem aplicadas, caso não tenham sido informadas explicitamente no prompt da demanda.

## 3. Conteúdo das Observações (Body)
- Todos os dados, resumos, métricas e entregáveis apresentados no chat após o cumprimento da tarefa devem ser transcritos integralmente no campo de observações (corpo) do compromisso.

## 4. Tipografia e Formatação (Courier New 10 pt)
- O corpo das observações deve ser formatado estritamente na fonte **Courier New tamanho 10 pt** via `WordEditor`:
  ```powershell
  $insp = $appt.GetInspector
  $doc = $insp.WordEditor
  if ($doc) {
      $range = $doc.Range()
      $range.Font.Name = "Courier New"
      $range.Font.Size = 10
  }
  ```

## 5. Rodapé de Rastreabilidade
- Sempre na última anotação de uma sequência ou sobre o tema em questão, o rodapé deve conter:
  ```text
  ================================================================================
  HISTÓRICO DA CONVERSA (ANTIGRAVITY CLI):
  agy --conversation=<conversation-id>
  ================================================================================
  ```
