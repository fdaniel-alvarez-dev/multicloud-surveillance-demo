# Guia Rápido

Siga este passo a passo para colocar o ambiente demo do Multicloud Surveillance no ar em menos de 30 minutos.

## 1. Solicite Acesso
1. Adquira o plano de acesso ao repositório ou resgate seu código de convite.
2. Informe o usuário ou e-mail do GitHub no checkout para liberarmos a permissão em até um dia útil.
3. Baixe o PDF "Start here" enviado no e-mail de confirmação com padrões de ambiente e links de FAQ.

## 2. Prepare Seu Sandbox
- Tenha um cluster Kubernetes (EKS, AKS ou GKE) ou utilize o script Kind incluído para testes locais.
- Garanta saída para os endpoints do AWS Kinesis, Azure Event Hub e Google Pub/Sub. O demo publica eventos sintéticos nas três nuvens.
- Instale o kit de CLIs: `kubectl`, `helm` e `terraform` v1.5+.

## 3. Faça o Deploy do Demo
1. Clone o repositório e troque para o último tag disponível.
2. Execute `./bootstrap-demo.sh` (referenciado no PDF) para provisionar recursos namespaced e fluxos de streaming de exemplo.
3. Aplique os manifestos de dashboards federados descritos em `docs/pt-BR/product-story.md` na seção _Ativos de Storytelling_.

## 4. Explore a Experiência
- **Dashboards:** acesse o link do Grafana exibido na saída do script para visualizar heatmaps e drilldowns.
- **Streams:** abra o player WebRTC (URL indicada na saída) para acompanhar transmissões ao vivo e replay.
- **Alertas:** acione os cenários de `FEATURES.md` para gerar notificações no PagerDuty e Slack.

## 5. Compartilhe Feedback
Precisa de demos estendidas, sessões compartilhadas ou integrações customizadas? Escreva para `solutions@multicloud-surveillance.demo` com o seu contexto.
