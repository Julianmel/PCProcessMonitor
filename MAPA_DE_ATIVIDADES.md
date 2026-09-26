# 🗺️ Mapa de Atividades - PCProcessMonitor

**Projeto:** PCProcessMonitor (Monitor de Infraestrutura Local & Dashboard NOC)  
**Data de Referência:** 25/09/2026  
**Responsável Técnico:** Julian & Antigravity (Google DeepMind)  
**Repositório:** `C:\Users\Julian\Dev\PCProcessMonitor`  
**Espelho de Produção:** `\\JFMELGACO-1\Technoflora-1\Documents\PCProcessMonitor` (`V:\`)  

---

## 📊 Resumo Executivo do Dia (25/09/2026)

| Métrica | Valor Consolidado |
|---|---|
| **Horário de Início:** | 14:15 |
| **Horário de Término:** | 20:58 |
| **Tempo Total Decorrido:** | ~6h 43min |
| **Tempo Efetivo de Desenvolvimento/Diagnóstico:** | ~6h 13min |
| **Sessões de Atividades Principais:** | 7 blocos estruturados |
| **Total de Commits Realizados:** | 22 commits |
| **Versões Lançadas:** | v1.0.0, v1.0.1, v1.0.2 |
| **Status Final do Sistema:** | 100% Operacional (4/4 nós ativos com usuário restrito + Dashboard com streaming em tempo real sem F5) |

---

## 📋 Detalhamento Cronológico das Atividades

### [Atividade 1] Publicação do Projeto e Solução da ISSUE #1 (Detecção Dinâmica do Host Local & Telemetria de I/O de Disco)
* **Data:** 25/09/2026
* **Hora Inicial:** 14:15
* **Hora Final:** 15:05
* **Tempo Gasto:** 50 minutos
* **Questionamento / Demanda:**
  * O script inicial utilizava a referência fixa `localhost` para a primeira máquina, causando duplicidade quando executado a partir de outros computadores da rede (`JFMELGACO-1`, `JFMELGACO-2`, `JFMELGACO-3`, `JFMELGACO3`).
  * Necessidade de adicionar telemetria de taxas de Leitura e Escrita do disco C: em tempo real.
* **Atividades Realizadas:**
  * Inicialização e estruturação do repositório Git local.
  * Criação do [`README.md`](file:///C:/Users/Julian/Dev/PCProcessMonitor/README.md) com documentação técnica e arquitetura Mermaid.
  * Implementação de detecção automática do nó local utilizando `$env:COMPUTERNAME` no [`Monitor-Rede.ps1`](file:///C:/Users/Julian/Dev/PCProcessMonitor/Monitor-Rede.ps1), marcando dinamicamente como `(Local)` e consultando os demais nós remotamente.
  * Implementação da coleta de taxas de I/O do Disco C: via classe WMI `Win32_PerfFormattedData_PerfDisk_LogicalDisk` (`DiskReadBytesPersec` e `DiskWriteBytesPersec`), com formatação dinâmica em KB/s e MB/s.
  * Adição de pré-checagem ultrarrápida via ICMP ping (*Fast Ping*), eliminando bloqueios de 12 segundos por máquina desligada.
  * Integração dos dados de I/O de disco no console com heatmap de cores (amarelo/verde) e no [`Build-HtmlDashboard.ps1`](file:///C:/Users/Julian/Dev/PCProcessMonitor/Build-HtmlDashboard.ps1).
  * Lançamento e fechamento oficial da **ISSUE #1** (Release **v1.0.1** - Commits `3fe91a0` até `c25cfd0`).

---

### [Atividade 2] Solução da ISSUE #2 (Negociação Dual-Protocol WinRM/DCOM, Suporte a Credenciais & Utilitário SetupHost)
* **Data:** 25/09/2026
* **Hora Inicial:** 15:10
* **Hora Final:** 17:25
* **Tempo Gasto:** 2 horas e 15 minutos
* **Questionamento / Demanda:**
  * Máquinas remotas do grupo de trabalho Technoflora apresentando falha de comunicação ou marcadas como `SEM ACESSO` / `OFFLINE` devido a restrições de Firewall e porta WinRM (5985) em redes de perfil público.
* **Atividades Realizadas:**
  * Implementação de mecanismo de conexão com negociação automática *Dual-Protocol*: tentativa primária via WinRM (WS-Management porta 5985) e *fallback* automático transparente para DCOM / RPC (porta 135 e portas dinâmicas) caso o WinRM seja bloqueado pelo perfil de rede.
  * Criação de novo status visual no console: distinção precisa entre `OFFLINE` (máquina desligada, sem ping) e `SEM ACESSO` (máquina ligada, mas com bloqueio de permissão de segurança).
  * Inclusão do parâmetro `-Credential` no [`Monitor-Rede.ps1`](file:///C:/Users/Julian/Dev/PCProcessMonitor/Monitor-Rede.ps1) para suportar autenticação remota em contas locais padronizadas.
  * Desenvolvimento do script utilitário [`Setup-MonitorHost.ps1`](file:///C:/Users/Julian/Dev/PCProcessMonitor/Setup-MonitorHost.ps1) para habilitar WinRM, TrustedHosts, portas de firewall e chave `LocalAccountTokenFilterPolicy` em nós remotos.
  * Validação das 4 máquinas ativas reportando telemetria em tempo real no console.
  * Lançamento e fechamento oficial da **ISSUE #2** (Release **v1.0.2** - Commits `4dfc838` e `2e20a04`).

---

### [Atividade 3] Automação de Inicialização e Provisionamento de Usuário Restrito sem Direitos de Administrador
* **Data:** 25/09/2026
* **Hora Inicial:** 17:30
* **Hora Final:** 18:05
* **Tempo Gasto:** 35 minutos
* **Questionamento / Demanda:**
  * "Não quero que ele seja Administrador." — O usuário `Monitor` (senha: `Monitor2026@`) precisa coletar dados de telemetria sem possuir privilégios administrativos em nenhuma das 4 máquinas.
  * Criação de launcher de clique duplo para execução descomplicada no host coletor.
* **Atividades Realizadas:**
  * Criação do arquivo de lote [`Iniciar-Monitor.bat`](file:///C:/Users/Julian/Dev/PCProcessMonitor/Iniciar-Monitor.bat) para execução direta do monitoramento no `JFMELGACO-1`.
  * Criação do script [`Configurar-MonitorLocal.ps1`](file:///C:/Users/Julian/Dev/PCProcessMonitor/Configurar-MonitorLocal.ps1) para provisionamento do usuário local `Monitor` sem inseri-lo no grupo de Administradores.
  * Atribuição exclusiva do usuário aos grupos de monitoramento do Windows (Performance Monitor Users, Performance Log Users, Distributed COM Users, Remote Management Users e Event Log Readers) (Commits `a9f2c90` e `a2ffec2`).

---

### [Atividade 4] Resolução Universal por SIDs, Firewall Global e Auto-Elevação
* **Data:** 25/09/2026
* **Hora Inicial:** 18:05
* **Hora Final:** 18:50
* **Tempo Gasto:** 45 minutos
* **Questionamento / Demanda:**
  * O script falhava ao adicionar o usuário aos grupos em computadores com Windows em idiomas distintos (PT-BR vs EN) ou quando executado sem privilégios elevados.
  * Criação de launcher automatizado para execução da configuração com um duplo clique.
* **Atividades Realizadas:**
  * Reestruturação do script [`Configurar-MonitorLocal.ps1`](file:///C:/Users/Julian/Dev/PCProcessMonitor/Configurar-MonitorLocal.ps1) para tradução dinâmica dos grupos locais através de seus SIDs universais conhecidos:
    * `S-1-5-32-558` (Performance Monitor Users)
    * `S-1-5-32-559` (Performance Log Users)
    * `S-1-5-32-562` (Distributed COM Users)
    * `S-1-5-32-580` (Remote Management Users)
    * `S-1-5-32-573` (Event Log Readers)
  * Liberação completa de regras de entrada no Windows Firewall para todos os perfis (`profile=any`): TCP 5985 (WinRM), TCP 135 (DCOM RPC), TCP 49152-65535 (RPC Dinâmico) e ICMP Echo (Ping).
  * Configuração da chave de registro `LocalAccountTokenFilterPolicy = 1`.
  * Criação do arquivo [`Configurar-MonitorLocal.bat`](file:///C:/Users/Julian/Dev/PCProcessMonitor/Configurar-MonitorLocal.bat) com auto-elevação via UAC (`Verb RunAs`) (Commits `fdb22d1` a `17b58bd`).

---

### [Atividade 5] Engenharia Reversa e Correção de Permissões WMI no JFMELGACO3 (Erro 0x80041003)
* **Data:** 25/09/2026
* **Hora Inicial:** 18:55
* **Hora Final:** 19:30
* **Tempo Gasto:** 35 minutos
* **Questionamento / Demanda:**
  * "Vish... Deu erro! Get-NetConnectionProfile: Falha de carregamento de provedor"
  * "Não mostrou ON LINE... Continua off line JFMELGACO3"
  * "Aviso no teste do Monitor: O comando 'ConvertTo-SecureString' foi encontrado no módulo 'Microsoft.PowerShell.Security', mas não foi possível carregar o módulo."
* **Atividades Realizadas:**
  * Investigação do log de eventos `Microsoft-Windows-WMI-Activity/Operational` (Evento 5858): identificada causa raiz no código de erro `0x80041003` (Acesso Negado na conexão ao namespace `root\cimv2`).
  * Análise de baixo nível do descritor de segurança do nó de referência `JFMELGACO-2` (onde o usuário `Monitor` funcionava 100% ONLINE):
    * Descoberto que o WMI exige descritores binários completos de **180 bytes** contendo cabeçalho estruturado com `Owner: S-1-5-32-544` (Administradores) e `Group: S-1-5-32-544`.
    * A síntese textual por SDDL anterior gerava estruturas com proprietário nulo, sendo rejeitadas pelo motor de segurança do WMI.
    * Confirmado que o usuário `Monitor` **não necessita de permissão modificada no namespace `root`** — o `root` foi restaurado ao padrão limpo universal do Windows de 144 bytes.
  * Implementação de clonagem binária bit-a-bit do descritor de 180 bytes no [`Configurar-MonitorLocal.ps1`](file:///C:/Users/Julian/Dev/PCProcessMonitor/Configurar-MonitorLocal.ps1), injetando no offset 36 os 28 bytes do SID local do `Monitor` do `JFMELGACO3` (`S-1-5-21-869974732-375269889-338688832-1009`).
  * Substituição do cmdlet `ConvertTo-SecureString` por instanciação direta em .NET (`New-Object System.Security.SecureString`), eliminando o conflito de metadados de tipo do PowerShell 5.1.
  * Execução da configuração no `JFMELGACO3`: transição imediata para **ONLINE** no `Monitor-Rede.ps1`, com **4/4 nós da rede ativos simultaneamente** (Commits `85062f6` e `17741bd`).

---

### [Atividade 6] Correção de Expressão Regular e Conversão Numérica no Dashboard HTML
* **Data:** 25/09/2026
* **Hora Inicial:** 19:30
* **Hora Final:** 20:40
* **Tempo Gasto:** 1 hora e 10 minutos
* **Questionamento / Demanda:**
  * "Problema: Dashboard não está mostrando os dados coletados."
  * Todas as medições e gráficos no painel HTML apareciam zerados (`0.0`).
* **Atividades Realizadas:**
  * Inspeção do código de leitura do log em [`Build-HtmlDashboard.ps1`](file:///C:/Users/Julian/Dev/PCProcessMonitor/Build-HtmlDashboard.ps1): identificado que o Regex de captura aceitava apenas dígitos e vírgulas (`[\d\,]+`), ignorando valores gravados com ponto decimal (`.`), como `12.9 GB`, `441.8 GB` e `8.8 MB/s`.
  * Como o grupo de telemetria era opcional, o Regex capturava apenas o nome da máquina e atribuía string vazia para as métricas, convertidas em `0` pelo PowerShell.
  * Correção do Regex para padrão universal com suporte a pontos e vírgulas (`[\d\.,]+`).
  * Desenvolvimento da função `Parse-MetricNumber` para normalização resiliente de números (tratando vírgula como decimal, ponto como separador de milhar e vice-versa, além de multiplicadores MB/s para KB/s).
  * Adição de busca dinâmica automática de logs na unidade mapeada da rede `V:\Documents\PCProcessMonitor\Data`.
  * Conversão e salvamento dos scripts em `UTF-8 com BOM` (`EF BB BF`), sanando distorções de acentuação (*mojibake*) no Windows PowerShell 5.1.
  * Reconstrução do [`dashboard_desempenho.html`](file:///C:/Users/Julian/Dev/PCProcessMonitor/dashboard_desempenho.html) com **391 pontos temporais** completamente preenchidos (Commit `afbcca6`).

---

### [Atividade 7] Implementação da Atualização Assíncrona Contínua de Dados (Eliminação Completa do F5)
* **Data:** 25/09/2026
* **Hora Inicial:** 20:40
* **Hora Final:** 20:58
* **Tempo Gasto:** 18 minutos
* **Questionamento / Demanda:**
  * "Beleza. Tá funcionando! Tem mais um problema... O 'refresh' da tela... É como um F5.. não gostei. Dá pra atualizar só os dados?"
  * Eliminar o recarregamento total da página (`location.reload()`) que causava tela branca piscando e perda de contexto.
* **Atividades Realizadas:**
  * Remoção definitiva do comando `window.location.reload()`.
  * Criação do pipeline desacoplado com geração automática do payload dinâmico `dashboard_data.js` a cada rodada do coletor.
  * Implementação da função `requestDataUpdate()` com estratégia híbrida inteligente:
    * Execução via `fetch()` assíncrono caso o dashboard seja servido via HTTP/HTTPS.
    * Injeção dinâmica de tag `<script id="dynamicDataScript">` caso aberto diretamente via protocolo local `file:///`, contornando bloqueios de CORS nativos de navegadores (Edge/Chrome).
  * Atribuição de identificadores únicos no DOM para mini-cards (`card_PC_cpu`, `card_PC_ram`, etc.) e células do modal estatístico para atualização pontual e instantânea.
  * Configuração do Chart.js com atualização no modo `chart.update('none')`, fazendo os gráficos deslizarem suavemente da direita para a esquerda sem recriar o Canvas nem causar cintilação.
  * Adição de pulso suave no indicador visual ciano (`livePulseDot`) a cada ciclo de atualização.
  * Sincronização automática de `dashboard_desempenho.html` e `dashboard_data.js` para a pasta de produção `V:\Documents\PCProcessMonitor`.
  * Atualização do `.gitignore` para omitir dados de telemetria transitórios (Commits `70643a6` e `d50f236`).

---

## 🏁 Quadro Comparativo: Antes vs. Depois

| Aspecto | Início do Dia (14:15) | Fim do Dia (20:58) |
|---|---|---|
| **Topologia de Rede** | Referência estática (`localhost`) causava conflito entre máquinas | Detecção dinâmica universal por `$env:COMPUTERNAME` |
| **I/O de Disco** | Inexistente (apenas espaço livre em GB) | Telemetria completa em tempo real de Leitura e Escrita (KB/s e MB/s) |
| **Protocolo de Rede** | WinRM exclusivo (falhava em perfis públicos de rede) | Negociação inteligente Dual-Protocol (WinRM com fallback para DCOM) |
| **Perfil do Usuário Monitor** | Dependia de privilégios de Administrador | Conta padrão estrita, sem nenhum direito administrativo em nenhum nó |
| **Status dos Computadores** | Nós remotos com `SEM ACESSO` ou `OFFLINE` | **4/4 nós ONLINE** com fluxo contínuo de dados (`JFMELGACO3`, `JFMELGACO-1`, `JFMELGACO-2`, `JFMELGACO-3`) |
| **Dashboard Web** | Dados zerados por incompatibilidade de Regex e recarregamento brusco via F5 a cada 5s | Exibição de 391+ pontos com streaming assíncrono contínuo e suave sem reload |
| **Versionamento Git** | Sem versionamento formal | 22 commits versionados e branch principal sincronizada |
