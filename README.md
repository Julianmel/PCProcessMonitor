    # 🖥️ PCProcessMonitor
    
    > **Sistema leve e autônomo de monitoramento de infraestrutura local em tempo real, com telemetria via PowerShell/WMI e Dashboard
  visual estilo NOC (Network Operations Center).**
    
    ![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-blue?logo=powershell)
    ![Interface](https://img.shields.io/badge/UI-TailwindCSS%20%2B%20Chart.js-38B2AC?logo=tailwind-css)
    ![Plataforma](https://img.shields.io/badge/Plataforma-Windows%2010%20%2F%2011-0078D6?logo=windows)
    ![Sem Dependências](https://img.shields.io/badge/Dependências-Zero%20Node%20%2F%20Zero%20Servidor-success)
    
    ---
    
    ## 🎯 Visão Geral
    
    O **PCProcessMonitor** foi desenvolvido para monitorar a saúde operacional (CPU, Memória RAM, Armazenamento em Disco e Tráfego de
  Rede) de múltiplas máquinas em uma rede local (Workgroup), sem a necessidade de instalar agentes pesados, servidores web dedicados ou
  bancos de dados complexos.
    
    O ecossistema é composto por dois scripts PowerShell e uma interface web moderna de alta densidade de informação:
    1. **`Monitor-Rede.ps1`**: Coletor contínuo de métricas via WMI/CIM com saída em terminal dinâmico (*in-place*) e persistência em
  logs.
    2. **`Build-HtmlDashboard.ps1`**: Gerador analítico que processa os logs brutos e constrói o painel HTML interativo.
    3. **`dashboard_desempenho.html`**: Dashboard em tela única (`100vh`) com fluxo temporal contínuo da direita para a esquerda (estilo
  Gerenciador de Tarefas do Windows).
    
    ---
    
    ## ⚡ Principais Características Técnicas
    
    ### 1. Coletor em Tempo Real (`Monitor-Rede.ps1`)
    - **Coleta Multimáquina via CIM/WMI:** Realiza consultas paralelizadas ou sequenciais leves aos nós da rede
  (`Win32_PerfFormattedData_PerfOS_Processor`, `Win32_OperatingSystem`, `Win32_LogicalDisk` e
  `Win32_PerfFormattedData_Tcpip_NetworkInterface`).
    - **Terminal In-Place sem Flickering:** Em vez de usar `Clear-Host` (que causa cintilação na tela), utiliza o reposicionamento do
  cursor (`[Console]::SetCursorPosition(0,0)`), garantindo uma atualização suave e contínua no prompt.
    - **Heatmap de Cores no Console:**
      - 🟡 **Amarelo:** Valores numéricos que aumentaram em relação ao ciclo anterior (maior consumo).
      - 🟢 **Verde:** Valores numéricos que diminuíram (alívio de consumo).
      - ⚪ **Branco:** Valores estáveis ou medição de referência inicial.
    - **Métricas de Rede Bidirecionais:** Exibe e registra as taxas de download (**Rx**) e upload (**Tx**) em KB/s e MB/s para cada
  computador.
    - **Rotação de Logs com Timestamp:** Cria automaticamente na inicialização arquivos organizados no formato:
      `AAAAMMDD - HHMM - PC Processmonitor.txt`.
    - **Gatilho Automático do Dashboard:** Dispara o script gerador de HTML a cada nova rodada de dados para manter o painel web sempre
  sincronizado.
    
    ---
    
    ### 2. Pipeline de Processamento Analítico (`Build-HtmlDashboard.ps1`)
    - **Detecção Inteligente do Último Log:** Localiza dinamicamente o arquivo de telemetria mais recente da pasta, sem necessidade de
  parâmetros manuais.
    - **Resiliência a Codificação (UTF-8 com BOM):** Leitura via `[System.IO.File]::ReadAllLines` e exportação com codificação UTF-8 com
  BOM, evitando problemas de caracteres corrompidos (*mojibake*) em ambientes Windows PowerShell 5.1 (PT-BR).
    - **Consolidação Estatística:** Calcula picos, médias operacionais e valores mínimos de cada nó para CPU, Memória e Rede.
    
    ---
    
    ### 3. Dashboard Web NOC (`dashboard_desempenho.html`)
    - **Visualização em Tela Única (`100vh` sem Rolagem):** Desenvolvido para monitores de operações (NOC), mantendo 100% dos dados e
  gráficos visíveis na viewport sem barras de rolagem.
    - **Alternador de Modos:** Botão flexível para alternar instantaneamente entre **🖥️ Modo Tela Única** e **📜 Modo Rolagem Clássico**.
    - **Fluxo Contínuo Estilo Gerenciador de Tarefas (Task Manager):**
      - Os dados entram pela extremidade direita (*"Agora"*) e deslizam continuamente para a esquerda a cada novo ciclo.
      - No início da coleta (poucas amostras), a linha parte da direita e avança sobre a grade vazia à esquerda, exatamente como no
  Windows Task Manager.
    - **Seletor de Janela Temporal com Memória:**
      - ⚡ **60 Amostras (Padrão)**
      - ⏱ **120 Amostras (~10 min)**
      - 📊 **Histórico Completo**
      - Preferência gravada automaticamente no `localStorage` do navegador.
    - **Grade 2x2 Adaptativa de Gráficos (Chart.js):**
      - Gráfico de CPU (%)
      - Gráfico de Memória RAM (%)
      - Gráfico de Download Rx (KB/s)
      - Gráfico de Upload Tx (KB/s)
      - Alternador de 1 clique para visualização de Armazenamento do Disco C:.
    - **Mini-Cards dos Computadores (46px):** Pílulas horizontais com status de conexão e métricas instantâneas de cada nó da rede.
    - **Auto-Refresh Integrado:** Contador regressivo de 5 segundos no cabeçalho com botões de `⏸ Pausar` e `▶ Retomar`.
    - **Modal Suspenso de Resumo Estatístico:** Botão `📋 Tabela Resumo` com exibição de tabela analítica completa (fechamento via `ESC`
  ou clique externo).
    
    ---
    
    ## 🏗️ Arquitetura do Sistema
    

  ┌─────────────────────────────────────────────────────────────┐
  │                      Nós da Rede Local                      │
  │   [JFMELGACO3]     [JFMELGACO-1]    [JFMELGACO-2]   ...     │
  └──────────────┬───────────────────────────────┬──────────────┘
  │ WMI / CIM                     │ WMI / CIM
  ▼                               ▼
  ┌─────────────────────────────────────────────────────────────┐
  │                    Monitor-Rede.ps1                         │
  │  - Coleta CPU, RAM, Disco C: e Tráfego de Rede (Rx/Tx)      │
  │  - Atualização In-Place com cores (Amarelo / Verde)         │
  │  - Gravação do arquivo de log timestamped                   │
  └──────────────────────────────┬──────────────────────────────┘
  │ Dispara a cada ciclo
  ▼
  ┌─────────────────────────────────────────────────────────────┐
  │                 Build-HtmlDashboard.ps1                     │
  │  - Seleciona o último log gerado                            │
  │  - Trata encoding UTF-8 com BOM (zero mojibake)             │
  │  - Calcula métricas, médias e picos                         │
  └──────────────────────────────┬──────────────────────────────┘
  │ Gera
  ▼
  ┌─────────────────────────────────────────────────────────────┐
  │                dashboard_desempenho.html                    │
  │  - Layout 100vh NOC (Tela única sem rolagem)                │
  │  - Chart.js com fluxo contínuo direita -> esquerda          │
  │  - Auto-refresh de 5s, seletores de janela e modal resumo   │
  └─────────────────────────────────────────────────────────────┘

    
    ---
    
    ## 📁 Estrutura de Arquivos
    
    ```text
    C:\Users\Julian\Dev\PCProcessMonitor\
    ├── Monitor-Rede.ps1                    # Script principal de telemetria e console in-place
    ├── Build-HtmlDashboard.ps1             # Gerador analítico do dashboard HTML
    ├── dashboard_desempenho.html           # Interface visual aberta no navegador
    └── AAAAMMDD - HHMM - PC Processmonitor.txt  # Logs gerados automaticamente por sessão
  ──────
  ## 🚀 Como Executar

  ### Pré-requisitos

  • Sistema Operacional: Windows 10 ou Windows 11.
  • PowerShell: Windows PowerShell 5.1 ou PowerShell 7+.
  • Rede Local: Máquinas configuradas no mesmo grupo de trabalho (ex: Technoflora) com permissão de consulta WMI/CIM na rede local.

  ### Passo a Passo

  1. Abra o terminal do PowerShell na pasta do projeto:
    cd "C:\Users\Julian\Dev\PCProcessMonitor"

  2. Inicie o monitoramento contínuo:
    .\Monitor-Rede.ps1
  O console passará a exibir o quadro atualizado em tempo real com destaque em amarelo para aumentos e verde para quedas.
  3. Abra o Dashboard no seu navegador:
      • Dê um duplo clique no arquivo dashboard_desempenho.html ou execute no PowerShell:

    Start-Process .\dashboard_desempenho.html
  A página se atualizará automaticamente a cada 5 segundos.
  ──────
  ## 🛠️ Tecnologias Utilizadas

  • PowerShell: Coleta de dados via WMI (Win32_*), manipulação de threads e I/O de arquivos.
  • Tailwind CSS: Estilização utilitária moderna para layout responsivo e modo escuro.
  • Chart.js: Renderização de gráficos temporais de alto desempenho em Canvas HTML5.
  • HTML5 / Vanilla JavaScript: Lógica de fluxo temporal, armazenamento local de preferências e auto-refresh sem dependência de
  frameworks pesados.

