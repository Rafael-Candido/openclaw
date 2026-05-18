# MEMORY.md - Cache Bootstrap do Notion

Gerado automaticamente a partir da base de conhecimento do Notion.
Este arquivo e apenas cache bootstrapado para contexto auxiliar.
A fonte de verdade continua sendo a API do Notion consultada em tempo de execucao.
Nao editar manualmente; rode `scripts/sync-notion-memory.sh` para atualizar.

- Fonte: bloco `2ed21016bd488033882be7b30727de5c`
- Sincronizado em: 2026-05-17 16:05:57 -0300

ENTRY 1
Resposta:
Respostas rápidas para as dúvidas mais comuns que surgem durante o processo de prospecção e venda. Consulte aqui antes de escalar para a supervisão.

ENTRY 2
Heading: 📦 Plataforma e Funcionamento
Pergunta: Como funciona o pagamento para a SmartEnvios?
Resposta:
O cliente adiciona crédito na plataforma e cada etiqueta gerada desconta automaticamente do saldo. Modalidade pré-paga padrão; pós-pago disponível mediante análise de crédito.

ENTRY 3
Heading: 📦 Plataforma e Funcionamento
Pergunta: O método de pagamento para inserção de crédito é somente por Pix?
Resposta:
Sim, apenas Pix no momento. Boleto e cartão de crédito estão previstos para o futuro.

ENTRY 4
Heading: 📦 Plataforma e Funcionamento
Pergunta: A SmartEnvios trabalha com NF e declaração de conteúdo?
Resposta:
Sim, ambas. Verificar no painel de transportadoras quais modalidades cada transportadora aceita.

ENTRY 5
Heading: 📦 Plataforma e Funcionamento
Pergunta: A SmartEnvios tem cotação de frete dentro do Bling?
Resposta:
Não. A integração com o Bling captura os pedidos, mas a cotação é feita pela plataforma de e-commerce. A seleção de frete diretamente no Bling não é possível por limitações da integração.

ENTRY 6
Heading: 📦 Plataforma e Funcionamento
Pergunta: Meu cadastro foi inativado. Como reativar?
Resposta:
Após 30 dias sem envios o sistema inativa automaticamente. Solicitar reativação na central de atendimento

ENTRY 7
Heading: 📦 Plataforma e Funcionamento
Pergunta: É possível ter dois cadastros com o mesmo CNPJ?
Resposta:
Sim. A plataforma permite o mesmo CNPJ em múltiplas contas para integrar lojas diferentes com faturamentos separados. O time de CS e Implantação, que tem acesso holding, faz a ativação e cada conta será conectada a uma loja do cliente.

ENTRY 8
Heading: 📦 Plataforma e Funcionamento
Pergunta: Quando desativa todas as transportadoras, na cotação constam como todas ativas. Isso é correto?
Resposta:
Sim, isso é correto. É uma medida de segurança para que o seller/embarcador não fique sem poder vender.

ENTRY 9
Heading: 📦 Plataforma e Funcionamento
Pergunta: Porque Danfe A4 e Simplificada vem sem vários dados preenchidos?
Resposta:
Para o envio do pedido, os dados fiscais detalhados da NF-e, como impostos, alíquotas, NCM, CFOP, CST/CSOSN etc., não são obrigatórios.
Os transportadores exigem, em regra, apenas a chave da NF-e, inclusive para validação em barreiras fiscais e continuidade normal do transporte. Por isso, a SmartEnvios permite que as plataformas integrem enviando apenas os dados do pedido + a chave da nota fiscal.
Outro ponto importante é que, quando o XML da NF-e não é enviado, as informações de volumes também não vêm da nota fiscal. Nesse cenário, a plataforma utiliza os dados do próprio pedido enviado pela integração — normalmente a quantidade de produtos do checkout — porque plataformas de e-commerce trabalham com produtos/pedidos e não com o conceito logístico/fiscal de pacotes e volumes da NF-e.
Para clientes que desejam trabalhar com apenas 1 volume/etiqueta independentemente da quantidade de itens do pedido, existe a opção de habilitar etiqueta única no cadastro. Assim, a plataforma sempre irá gerar apenas 1 etiqueta.
Caso seja necessário ajustar a quantidade de volumes antes da impressão, isso também pode ser feito manualmente no portal antes de gerar a etiqueta.
Para clientes que utilizam API, também disponibilizamos o endpoint de atualização (PATCH), onde é possível enviar a quantidade correta de volumes antes da impressão da etiqueta, garantindo que a expedição ocorra conforme a necessidade operacional do cliente.
Sem o XML da NF-e, algumas informações da DANFE e dos detalhes fiscais podem ficar incompletas ou limitadas, como:
- Cidade e UF completas
- Dados tributários dos itens
- Valores fiscais detalhados
- Informações de frete da NF
- Volumes e transporte conforme emitido na nota
Para que a plataforma apresente todos os dados completos da NF-e, é necessário enviar o XML por um destes caminhos:
1. Encaminhamento automático para nf@smartenvios.com
1. Upload manual do XML no pedido
1. Sincronização/envio do XML pela Wbuy via integração/API

ENTRY 10
Heading: 📦 Pedidos e Etiquetas
Pergunta: Qual o prazo de validade da etiqueta após impressa?
Resposta:
7 dias. Após esse prazo, a etiqueta volta ao status "pronto para enviar" e precisa ser reimpressa.

ENTRY 11
Heading: 📦 Pedidos e Etiquetas
Pergunta: Qual o prazo de validade de etiquetas reversas?
Resposta:
30 dias contados da data de emissão.

ENTRY 12
Heading: 📦 Pedidos e Etiquetas
Pergunta: O cliente cancelou um pedido antes de desvincular a NF e não consegue reutilizá-la. Como resolver?
Resposta:
O cliente precisa abrir um ticket para que o time de suporte desvincule a NF manualmente.

ENTRY 13
Heading: 📦 Pedidos e Etiquetas
Pergunta: Por que não aparece a opção de desvincular a nota fiscal do pedido?
Resposta:
Se o pedido estiver com etiqueta impressa ou cancelado, o sistema não permite desvincular. O time de suporte pode:
- Para pedidos cancelados: trocar o status para "Pedido em Aberto"
- Para etiqueta impressa: clicar no lápis de editar os dados de destino para retornar o pedido para "Pronto para Envio"

ENTRY 14
Heading: 📦 Pedidos e Etiquetas
Pergunta: Se cancelar um pedido na SmartEnvios, ele reflete nas plataformas de e-commerce?
Resposta:
Não. O cancelamento afeta apenas o recebimento da expedição SmartEnvios. Plataformas e ERPs integrados não recebem essa informação.

ENTRY 15
Heading: 📦 Pedidos e Etiquetas
Pergunta: Criar pedidos a partir da nota fiscal não funciona. O que verificar?
Resposta:
Em Configurações → Cadastro → Embarcadores, checar se a tag de "Processamento de NF-e" está como automático. Se estiver como manual, vai apenas tentar vincular a pedidos existentes. A opção automático permite criar pedidos a partir da nota.

ENTRY 16
Heading: 📦 Pedidos e Etiquetas
Pergunta: Vínculo de nota fiscal via API não funciona. O que verificar?
Resposta:
Conferir se os dados do pedido criado correspondem aos dados da nota: CNPJ remetente, CEP remetente, CEP destinatário, CPF destinatário, número do destinatário, etc.

ENTRY 17
Heading: 📦 Pedidos e Etiquetas
Pergunta: Erro desconhecido na importação do XML da nota fiscal. O que fazer?
Resposta:
Antes de acionar o time técnico, verificar:

ENTRY 18
Heading: 📦 Pedidos e Etiquetas
Pergunta: O CNPJ da transportadora está de acordo com as transportadoras disponíveis ao cliente?

ENTRY 19
Heading: 📦 Pedidos e Etiquetas
Pergunta: O peso bruto e líquido do XML estão preenchidos?

ENTRY 20
Heading: 📦 Pedidos e Etiquetas
Pergunta: O CNPJ do emitente da nota é o mesmo do embarcador?

ENTRY 21
Heading: 📦 Pedidos e Etiquetas
Pergunta: Os CEP’s do destinatário e remetente são válidos no Busca CEP dos Correios?
Resposta:
Se após essas verificações o erro persistir, consultar os logs de integração de XML.

ENTRY 22
Heading: 📦 Pedidos e Etiquetas
Pergunta: O pedido foi cotado com uma transportadora, mas quando importou para a SmartEnvios selecionou outra. Por quê?
Resposta:
A transportadora selecionada na cotação pode não estar ativada no painel da SmartEnvios. Verificar no log de observação do pedido e conferir se a transportadora está ativa em Configurações → Transportadoras, filtrando pelo cliente.

ENTRY 23
Heading: 📦 Pedidos e Etiquetas
Pergunta: Dados do XML da nota fiscal são diferentes dos dados apresentados na plataforma. Por quê?
Resposta:
A plataforma permite enviar o pedido com nota fiscal usando apenas a chave ou enviando pelo XML. Quando se usa apenas a chave, os dados do pedido são os importados da integração (do e-commerce). Se o dado da venda no e-commerce é diferente do que foi emitido, será considerado os dados do e-commerce. Para usar os dados do XML, é necessário enviá-lo pelo portal ou por nf@smartenvios.com.
No cadastro do embarcador há uma flag chamada "Volume único para integrações". Quando estiver como "sim", sai apenas uma etiqueta e só sairá mais de uma com alteração manual pelo lápis. Se o cliente fizer envios frequentes com múltiplos volumes, deixe a flag como "não".

ENTRY 24
Heading: 📦 Pedidos e Etiquetas
Pergunta: Quando o cliente já utiliza o contrato da transportadora via SmartEnvios e quer utilizar o contrato próprio, é possível?
Resposta:
Sim, basta apenas realizar as configurações, alterando o contrato da SmartEnvios para o contrato próprio do embarcador com a transportadora.

ENTRY 25
Heading: 📏 Pesos e Dimensões
Pergunta: O cliente está recebendo uma cotação muito alta porque o peso está 100x maior. O que pode ser?
Resposta:
A plataforma (especialmente a Irroba) pode estar enviando pesos com escala diferente no checkout. O cliente precisa revisar a configuração de peso na plataforma.

ENTRY 26
Heading: 📏 Pesos e Dimensões
Pergunta: Na cotação em massa usando planilha, como o peso é calculado?
Resposta:
O peso é sempre considerado no primeiro volume; os demais ficam com 0,01.

ENTRY 27
Heading: ⚙️ Configurações e Usuários
Pergunta: Como alterar o Hub do cliente?
Resposta:
Na plataforma SmartEnvios: Configurações → Cadastros → Embarcadores → Editar → campo Hub. Lembrar de limpar as tabelas antigas e vincular as novas.

ENTRY 28
Heading: ⚙️ Configurações e Usuários
Pergunta: É possível desativar as notificações de rastreamento por e-mail e WhatsApp?
Resposta:
Sim. Em Configurações → Cadastros → editar o cliente → campo Notificação → remover ou adicionar as opções desejadas.

ENTRY 29
Heading: ⚙️ Configurações e Usuários
Pergunta: Como visualizar quem fez modificações no cadastro do cliente?
Resposta:
Usar o painel do Metabase: Histórico de Modificações em Cadastros.

ENTRY 30
Heading: ⚙️ Configurações e Usuários
Pergunta: Como visualizar quem realizou modificações em um pedido?
Resposta:
Usar o painel do Metabase: Histórico de Modificações em Pedidos.

ENTRY 31
Heading: ⚙️ Configurações e Usuários
Pergunta: Como filtrar pedidos integrados que são SmartEnvios?
Resposta:
Na plataforma, na tela de Pedidos, usar o filtro "Serviço SmartEnvios". Ele listará apenas os pedidos com cotação SmartEnvios.

ENTRY 32
Heading: ⚙️ Configurações e Usuários
Pergunta: Se o usuário estiver sem acesso a algum recurso da plataforma, como resolver? / Como alterar o perfil do usuário?
Resposta:
Editar o usuário indo em Configurações → Cadastro → Usuário, alterar o perfil e salvar.

ENTRY 33
Heading: ⚙️ Configurações e Usuários
Pergunta: O prazo de entrega está considerando um dia a mais por conta do dia da coleta. Como corrigir?
Resposta:
Se todos os pedidos da transportadora forem embarcados no mesmo dia da coleta, a tabela pode ser ajustada. Se houver clientes que coletam à tarde mas não embarcam no mesmo dia, não é possível via tabela. A alternativa é criar uma regra de frete para reduzir 1 dia para aquele embarcador específico e aquela transportadora.

ENTRY 34
Heading: ⚙️ Configurações e Usuários
Pergunta: Cliente informou que não está recebendo as notificações de webhook. Como verificar?
Resposta:
Consultar o painel Metabase de logs: Detalhes de Webhook.

ENTRY 35
Heading: ⚙️ Configurações e Usuários
Pergunta: Como integrar nota fiscal pela WBUY?
Resposta:
Se o ERP do cliente tiver integração de nota fiscal com a WBuy, a integração da SmartEnvios puxará automaticamente a chave da nota.

ENTRY 36
Heading: ⚙️ Configurações e Usuários
Pergunta: Cliente quer a tela de rastreio personalizada. Quais informações ele precisa enviar?
Resposta:
Para darmos continuidade à solicitação, precisamos das seguintes informações:
- Cor primária (usada em títulos e botões principais)
- Cor secundária (usada em botões de destaque/ativos)
- Cor do texto (usada no corpo dos parágrafos)
- Logo da empresa
- Banner publicitário 01 — Tamanho: 728 x 850 pixels
- Banner publicitário 02 — Tamanho: 1300 x 300 pixels
Para visualizar onde cada elemento será aplicado, acessar o tutorial: https://smartenvios.zendesk.com/hc/pt-br/articles/48586089702035

ENTRY 37
Heading: ⚙️ Configurações e Usuários
Pergunta: Como configurar o WhatsApp Business?
Resposta:
Configuração do WhatsApp Business com BRfone

ENTRY 38
Heading: 🔗 Integrações
Pergunta: A SmartEnvios integra com qual plano da Shopify?
Resposta:
Grow (anual), Advanced e Plus. Para Basic, cotação via Frenet contratada pelo canal da Shopify.

ENTRY 39
Heading: 🔗 Integrações
Pergunta: Clientes novos da Loja Integrada usam a Frenet para cotação, enquanto os antigos não. Por quê?
Resposta:
No passado, a SmartEnvios tinha um app de cotação próprio na Loja Integrada, mas ele não está mais disponível. Atualmente, a única forma de cotar na LI é via Frenet. Para novos embarcadores, a cotação só pode ser feita via Frenet. Não há app oficial da SmartEnvios na LI.

ENTRY 40
Heading: 🔗 Integrações
Pergunta: A SmartEnvios tem alguma tratativa para integração com a Intelipost?
Resposta:
Não há tratativas ativas no momento.

ENTRY 41
Heading: 🔗 Integrações
Pergunta: Clientes VTEX que usam Intelipost podem manter ambas as integrações?
Resposta:
Sim. A SmartEnvios pode ser integrada na VTEX e o cliente pode manter a Intelipost para leilão de frete em paralelo.

ENTRY 42
Heading: 🔗 Integrações
Pergunta: A SmartEnvios tem uma conta Frenet disponível para novas implantações?
Resposta:
Sim. Usamos a mesma conta Frenet para os clientes do Hub.

ENTRY 43
Heading: 🔗 Integrações
Pergunta: A OpenCart pode integrar com a SmartEnvios?
Resposta:
Sim, via Frenet. O cliente pode usar sua própria conta Frenet ou a da SmartEnvios.

ENTRY 44
Heading: 🔗 Integrações
Pergunta: O cliente pode integrar Bling, manter a NuvemShop e adicionar Shopify via Frenet ao mesmo tempo?
Resposta:
Sim, mas os pedidos de todos os e-commerces aparecerão juntos na tela de Pedidos de Frete.

ENTRY 45
Heading: 🔗 Integrações
Pergunta: A SmartEnvios tem transportadoras que não estão disponíveis na Frenet?
Resposta:
Sim. Log Manager, GFL, J&T, Buslog e Transwells não estão na Frenet — só estão disponíveis diretamente na SmartEnvios.

ENTRY 46
Heading: 🔗 Integrações
Pergunta: Clientes WooCommerce enfrentam problemas com cotação?
Resposta:
Alguns plugins podem interferir. Não há um plugin específico identificado como universalmente incompatível, mas é um ponto a checar se a cotação não retornar.

ENTRY 47
Heading: 🔗 Integrações
Pergunta: Temos integração com VTEX e Linx Millennium?
Resposta:
Sim. Se o ERP Linx enviar XMLs por e-mail ou alimentar a VTEX com URL pública de NF, conseguimos atualizar os pedidos.

ENTRY 48
Heading: 🔗 Integrações
Pergunta: Inovarti — temos integração?
Resposta:
Não há integração nativa para cálculo de frete. Verificar se a plataforma integra com a Frenet e fazer através dela.

ENTRY 49
Heading: 🔗 Integrações
Pergunta: O lead usa uma plataforma sem integração nativa. O que fazer?
Resposta:
Informar que conectaremos a um especialista para avaliar viabilidade e prazo de integração.
Poucas transportadoras aparecem no painel do cliente.
O time de especialistas habilitará mais opções. Jadlog e Correios disponíveis nacionalmente; outras transportadoras sob consulta por região e volume.

ENTRY 50
Heading: 🔗 Integrações
Pergunta: Pedido da plataforma JET não integrou ou não atualizou rastreio. O que fazer?
Resposta:
A integração com a JET foi desenvolvida por eles. Se em nosso portal estiver corretamente atualizado, é necessário o cliente entrar em contato com o suporte da JET para verificar o motivo. Caso seja identificado algum erro em nossa API, pode ser aberto um ticket com o request e response que o parceiro está fazendo para ajudarmos a resolver.

ENTRY 51
Heading: 🔗 Integrações
Pergunta: Pedido da plataforma Magazord não integrou ou não atualizou rastreio. O que fazer?
Resposta:
A integração com a Magazord foi desenvolvida por eles. Se em nosso portal estiver corretamente atualizado, é necessário o cliente entrar em contato com o suporte da Magazord para verificar o motivo. Caso seja identificado algum erro em nossa API, pode ser aberto um ticket com o request e response que o parceiro está fazendo para ajudarmos a resolver.

ENTRY 52
Heading: 🔗 Integrações
Pergunta: Pedido do ERP Softup não integrou ou não atualizou rastreio. O que fazer?
Resposta:
A integração com a Softup foi desenvolvida por eles. Se em nosso portal estiver corretamente atualizado, é necessário o cliente entrar em contato com o suporte da Softup para verificar o motivo. Caso seja identificado algum erro em nossa API, pode ser aberto um ticket com o request e response que o parceiro está fazendo para ajudarmos a resolver.

ENTRY 53
Heading: 🔗 Integrações
Pergunta: Quero integrar alguma ferramenta, plataforma ou ERP com a SmartEnvios. O que faço?
Resposta:
- Se for uma plataforma, ERP ou transportador querendo ser parceiro: encaminhar o interesse para parcerias@smartenvios.com.
- Se for um cliente querendo consumir a API: usar os recursos da API pública e o token disponível em Configurações → Integrações → Card SmartEnvios → Token SmartEnvios. Encaminhar a documentação da API e o token ao desenvolvedor. Dúvidas sobre a API: engenharia@smartenvios.com.

ENTRY 54
Heading: 🛠️ Integrações com terceiros (desenvolvidas pelos parceiros)
Resposta:
As integrações abaixo foram desenvolvidas pelos próprios parceiros. Qualquer problema de integração deve ser acionado diretamente a eles, com prova do fornecimento dos dados por parte da SmartEnvios:

ENTRY 55
Heading: 🛠️ Integrações com terceiros (desenvolvidas pelos parceiros)
Resposta:
- GFL

ENTRY 56
Heading: 🛠️ Integrações com terceiros (desenvolvidas pelos parceiros)
Resposta:
- DBA Express

ENTRY 57
Heading: 🛠️ Integrações com terceiros (desenvolvidas pelos parceiros)
Resposta:
- Buslog

ENTRY 58
Heading: 🛠️ Integrações com terceiros (desenvolvidas pelos parceiros)
Resposta:
Transportadoras de rodo médio ou pesado, integram normalmente os pedidos usando notifis, atualizam o rastreio usando ocoren, sempre que algo não acontecer, precisa checar os documentos emitidos para o email notifis@smartenvios.com e ocoren@smartenvios.com para verificar se chegaram e se estão no formato esperado

ENTRY 59
Heading: 🛠️ Integrações com terceiros (desenvolvidas pelos parceiros)
Resposta:
Integração transportadoras

ENTRY 60
Heading: 🚚 Coleta e Logística
Pergunta: Como funciona a coleta?
Resposta:
Mínimo de 20 pedidos/dia para garantir rota sustentável. Abaixo disso, o cliente leva nos pontos parceiros. Mapa de Pontos

ENTRY 61
Heading: 🚚 Coleta e Logística
Pergunta: Ponto de coleta muito distante da loja do cliente. O que dizer?
Resposta:
Estamos expandindo constantemente. Indicar pontos alternativos disponíveis na região.
Ponto de coleta alternativo em Ribeirão Preto:
Rua Lafaiete, 593 — Estacionamento SAMPARK.

ENTRY 62
Heading: 🚚 Coleta e Logística
Pergunta: Como verificar qual Hub atenderá um novo cliente?
Resposta:
Informar o endereço completo do cliente e validar com o time de Operações qual Hub tem cobertura para o CEP e a volumetria informada.

ENTRY 63
Heading: 🚚 Coleta e Logística
Pergunta: Fazem envios com origem fora do Brasil?
Resposta:
Sim: Envio Internacional SmartEnvios.

ENTRY 64
Heading: 🚚 Coleta e Logística
Pergunta: É possível usar a Uber como reversa?
Resposta:
Sim. Realizar cotação reversa na plataforma da SmartEnvios, invertendo o endereço do consumidor como origem e o endereço da loja como destino.

ENTRY 65
Heading: 🚚 Coleta e Logística
Pergunta: Logística reversa — quais transportadoras estão disponíveis?
Resposta:
A logística reversa é feita exclusivamente por Correios (Sedex ou PAC).

ENTRY 66
Heading: 🚚 Coleta e Logística
Pergunta: Como saber se um pedido foi integrado com a Loggi quando não aparece no portal deles?
Resposta:
Baixar o FileZilla Client, usar as credenciais do FTP da Loggi, acessar a pasta /in/backup e buscar o código de rastreio (Ctrl+F). Credenciais do FTP disponíveis no Discord.

ENTRY 67
Heading: 🚚 Coleta e Logística
Pergunta: Um cliente atualizou o endereço de coleta e tinha emitido notas no endereço antigo. Precisa cancelar e refazer?
Resposta:
Se for na mesma cidade, não precisa alterar. Se for em outra cidade, precisa emitir novas notas e cancelar no SEFAZ.

ENTRY 68
Heading: 💰 Financeiro
Pergunta: Quais são as datas de fechamento de fatura?
Resposta:
As datas são pré-estabelecidas e fechadas com 7 dias de antecedência para o vencimento do boleto.

ENTRY 69
Heading: 💰 Financeiro
Pergunta: O valor da nota fiscal está divergente na plataforma. O que verificar?
Resposta:
- Se a integração for feita por sistema externo (ERP), é ele o responsável por enviar peso, valor e volumes.
- Se a NF for importada via XML completo, a SmartEnvios substitui os valores pelo XML.
- Se for enviada apenas a chave da nota, a substituição não ocorre — os dados originais do pedido são mantidos.

ENTRY 70
Heading: 💬 Atendimento e Direcionamentos
Resposta:
Cliente com problema em um envio.

ENTRY 71
Heading: 💬 Atendimento e Direcionamentos
Resposta:
Suporte via WhatsApp: (16) 3600 8101.

ENTRY 72
Heading: 💬 Atendimento e Direcionamentos
Resposta:
Consumidor final perguntando sobre rastreio.

ENTRY 73
Heading: 💬 Atendimento e Direcionamentos
Resposta:
Link público: portal.smartenvios.com/rastreamento.

ENTRY 74
Heading: 💬 Atendimento e Direcionamentos
Resposta:
E-mail de consumidor final sobre o pedido dele.

ENTRY 75
Heading: 💬 Atendimento e Direcionamentos
Resposta:
Redirecionar para: suporte@smartenvios.com.

ENTRY 76
Heading: 💬 Atendimento e Direcionamentos
Resposta:
Interesse em parceria comercial.

ENTRY 77
Heading: 💬 Atendimento e Direcionamentos
Resposta:
Enviar apresentação para: parcerias@smartenvios.com.

ENTRY 78
Heading: 💬 Atendimento e Direcionamentos
Resposta:
Interesse em contratar motoristas ou fazer entregas para a SmartEnvios.

ENTRY 79
Heading: 💬 Atendimento e Direcionamentos
Resposta:
Redirecionar para: +55 16 99148-6897.

ENTRY 80
Heading: 💬 Atendimento e Direcionamentos
Resposta:
Quando o transportador der prazo para entregas.

ENTRY 81
Heading: 💬 Atendimento e Direcionamentos
Resposta:
Fechar o ticket, colocando a mensagem de que, caso não seja entregue, o cliente reabra o ticket.

ENTRY 82
Heading: 💬 Atendimento e Direcionamentos
Resposta:
Quando o cliente solicitar contato por telefone ou WhatsApp no momento da entrega.

ENTRY 83
Heading: 💬 Atendimento e Direcionamentos
Resposta:
Fechar o ticket, colocando a informação de que a mensagem será repassada ao transportador, porém este não é um procedimento garantido por não se tratar de uma medida padrão do transportador.

ENTRY 84
Heading: 💬 Atendimento e Direcionamentos
Resposta:
Quando um cliente solicitar prioridade na entrega.

ENTRY 85
Heading: 💬 Atendimento e Direcionamentos
Resposta:
Fechar o ticket, colocando a informação de que a mensagem será repassada ao transportador solicitando prioridade na entrega.

ENTRY 86
Heading: 🎫 Zendesk e Atendimento Interno
Resposta:
Erro 404 ao tentar acessar o ticket aberto.

ENTRY 87
Heading: 🎫 Zendesk e Atendimento Interno
Resposta:
Isso acontece quando o usuário que quer visualizar não pertence à organização ou não está como seguidor do ticket. Para resolver: vá até o ticket em questão, identifique se o usuário associado é embarcador ou consumidor; se for embarcador, vincule o usuário à organização clicando sob seu nome. Além disso, configurar: "pode visualizar tickets da organização do usuário" e na organização "pode visualizar todos os tickets da organização e adicionar comentários". Assim, todos os usuários associados à organização poderão ver todos os tickets.

ENTRY 88
Heading: 🎫 Zendesk e Atendimento Interno
Pergunta: Tickets estão sendo atribuídos para o grupo errado. Como corrigir?
Resposta:
Verificar se a organização do usuário está corretamente atribuída para o hub ao qual ele pertence e se o ticket possui uma organização vinculada.

ENTRY 89
Heading: 🎫 Zendesk e Atendimento Interno
Pergunta: Atendente não está conseguindo acessar o WhatsApp do time. Como verificar?
Resposta:
Ir até o usuário do atendente no Zendesk, editar e habilitar o checkbox de chat.
Cliente quer alterar o e-mail de cadastro para tratativas de ticket.
Criar um novo usuário na plataforma em Configurações → Usuário (que sincronizará automaticamente com o Zendesk). Depois, trocar a ordem dos e-mails da organização para que os preventivos abram no e-mail principal correto e revisar se tudo ocorreu corretamente.

ENTRY 90
Heading: 🛠️ Soluções da SmartEnvios — resumo para o discurso
Resposta:
1. Frete mais barato com 20+ transportadoras integradas

ENTRY 91
Heading: 🛠️ Soluções da SmartEnvios — resumo para o discurso
Resposta:
1. Cotação automática no painel — individual ou em massa

ENTRY 92
Heading: 🛠️ Soluções da SmartEnvios — resumo para o discurso
Resposta:
1. Reversa Fácil — automação de trocas e devoluções

ENTRY 93
Heading: 🛠️ Soluções da SmartEnvios — resumo para o discurso
Resposta:
1. Auditoria de fretes — paga apenas o que foi cotado

ENTRY 94
Heading: 🛠️ Soluções da SmartEnvios — resumo para o discurso
Resposta:
1. Notiflow — notificações automáticas de rastreio via WhatsApp

ENTRY 95
Heading: 🛠️ Soluções da SmartEnvios — resumo para o discurso
Resposta:
1. Regras de cotação avançadas — frete grátis estratégico por ticket médio

ENTRY 96
Heading: 🛠️ Soluções da SmartEnvios — resumo para o discurso
Resposta:
1. Torre de controle — visibilidade de toda a jornada do pedido

ENTRY 97
Heading: 🛠️ Soluções da SmartEnvios — resumo para o discurso
Resposta:
1. Conta corrente inteligente — pré-pago e pós-pago disponíveis

ENTRY 98
Heading: 🛠️ Soluções da SmartEnvios — resumo para o discurso
Resposta:
Resultados que buscamos: torre de controle operacional, impulso em vendas, fidelização, redução de custos, eficiência operacional e controle estratégico.

ENTRY 99
Heading: 🚛 Processos por Transportadora
Resposta:
Consulte os processos operacionais de cada transportadora antes de acionar suporte ou supervisão.

ENTRY 100
Heading: 📦 Gollog
Resposta:
Status: Ativo | Cotação: Frenet | Docs aceitos: NF e DC

ENTRY 101
Heading: 📦 Gollog
Resposta:
Prazos: Atraso 3 d.u. | Busca 4 d.u. | Acareação 4 d.u. | Extravio 30 d.c. | Avaria 30 d.c. | Devolução = prazo de entrega

ENTRY 102
Heading: 📦 Gollog
Resposta:
Atenção: Atendimento somente com NF para os estados CE, PB, PE e MS.

ENTRY 103
Heading: 📦 Gollog
Resposta:
Processo de Busca (Pedido em atraso) | Processo Acareção | Análise de Extravio | Processo de retenção fiscal | Informações importantes

ENTRY 104
Heading: 📦 Gollog
Resposta:
📄 Ver página completa da Gollog

ENTRY 105
Heading: 📦 Jadlog
Resposta:
Status: Ativo | Cotação: Planilha | Docs aceitos: NF e DC (DC até R$1.500)

ENTRY 106
Heading: 📦 Jadlog
Resposta:
Prazos: Atraso 3 d.u. | Busca 9 d.u. | Acareação 9 d.u. | Extravio 9 d.u. | Avaria 30 d.u. | Devolução 30 d.u.

ENTRY 107
Heading: 📦 Jadlog
Resposta:
Processo de Busca (Pedido em atraso) | Processo Acareção | Análise de Extravio

ENTRY 108
Heading: 📦 Jadlog
Resposta:
📄 Ver página completa da Jadlog

ENTRY 109
Heading: 📦 Buslog
Resposta:
Status: Ativo | Docs aceitos: NF

ENTRY 110
Heading: 📦 Buslog
Resposta:
Prazos: Atraso 3 d.u. | Busca 3 d.u. | Acareação 3 d.u. | Extravio 3 d.u. | Avaria 5 d.u. | Devolução 15 d.u.

ENTRY 111
Heading: 📦 Buslog
Resposta:
Processo de Busca (Pedido em atraso)

ENTRY 112
Heading: 📦 Buslog
Resposta:
📄 Ver página completa da Buslog

ENTRY 113
Heading: 📦 GFL / Magalog
Resposta:
Status: Ativo | Docs aceitos: NF

ENTRY 114
Heading: 📦 GFL / Magalog
Resposta:
Prazos: Atraso 3 d.u. | Busca 3 d.u. | Acareação 3 d.u. | Extravio 3 d.u. | Avaria 5 d.u. | Devolução 15 d.u.

ENTRY 115
Heading: 📦 GFL / Magalog
Resposta:
Processo de Busca (Pedido em atraso) | Processo Acareção | Processo de Avaria | Alteração/Correção de Endereço | Devolução | Informações importantes

ENTRY 116
Heading: 📦 GFL / Magalog
Resposta:
📄 Ver página completa da GFL

ENTRY 117
Heading: 📦 Transwells
Resposta:
Status: Ativo | Docs aceitos: NF | Rastreio: transwells.com.br/rastreamento

ENTRY 118
Heading: 📦 Transwells
Resposta:
Limite de peso: 350 kg | Fator de cubagem: 300

ENTRY 119
Heading: 📦 Transwells
Resposta:
📄 Ver página completa da Transwells

ENTRY 120
Heading: 📦 Leofran
Resposta:
Status: Ativo | Docs aceitos: NF

ENTRY 121
Heading: 📦 Leofran
Resposta:
Prazos: Atraso 3 d.u. | Busca 4 d.u. | Acareação 4 d.u. | Extravio 4 d.u. | Avaria 4 d.u. | Devolução 30 d.u.

ENTRY 122
Heading: 📦 Leofran
Resposta:
Rastreio via chave NFe: ssw.inf.br/2/rastreamento_danfe

ENTRY 123
Heading: 📦 Leofran
Resposta:
📄 Ver página completa da Leofran

ENTRY 124
Heading: 📦 Correios (PAC / Sedex)
Resposta:
Status: Ativo | Docs aceitos: NF e DC | Pesos: até 30 kg

ENTRY 125
Heading: 📦 Correios (PAC / Sedex)
Resposta:
Prazos: Atraso 5 d.u. | Busca 5 d.u. | Acareação 5 d.u. | Extravio 5 d.u. | Avaria 5 d.u. | Devolução = prazo de entrega

ENTRY 126
Heading: 📦 Correios (PAC / Sedex)
Resposta:
DC máximo: Sedex R$10.000 | PAC R$3.000

ENTRY 127
Heading: 📦 Correios (PAC / Sedex)
Resposta:
Pedido em atraso | Informações importantes

ENTRY 128
Heading: 📦 Correios (PAC / Sedex)
Resposta:
📄 Ver página completa dos Correios

ENTRY 129
Heading: 📦 Loggi
Resposta:
Status: Ativo | Docs aceitos: NF e DC (DC até R$1.000)

ENTRY 130
Heading: 📦 Loggi
Resposta:
Prazos: Atraso 3 d.u. | Busca 4 d.u. | Acareação 4 d.u. | Extravio 4 d.u. | Avaria 4 d.u. | Devolução 20 d.c.

ENTRY 131
Heading: 📦 Loggi
Resposta:
Processo de Busca (Pedido em atraso) | Processo Acareção | Processo de Avaria | Alteração/Correção de Endereço | Devolução | Informações importantes

ENTRY 132
Heading: 📦 Loggi
Resposta:
📄 Ver página completa da Loggi

ENTRY 133
Heading: 📦 J&T
Resposta:
Status: Ativo

ENTRY 134
Heading: 📦 J&T
Resposta:
Prazos: Atraso 2 d. | Busca 3 d. | Acareação 10 d. | Extravio 8 d. | Avaria 5 d. | Devolução 20 d.

ENTRY 135
Heading: 📦 J&T
Resposta:
Processo de Busca (Pedido em atraso) | Processo Acareção | Processo de Avaria | Alteração/Correção de Endereço | Devolução | Informações importantes

ENTRY 136
Heading: 📦 J&T
Resposta:
📄 Ver página completa da J&T

ENTRY 137
Heading: 📦 Imile
Resposta:
Status: Implantação | Docs aceitos: NF

ENTRY 138
Heading: 📦 Imile
Resposta:
Prazos: Atraso 3 d.u. | Busca 5 d.u. | Acareação 3 d.u. | Extravio 10 d.u. | Avaria 10 d.u. | Devolução 2x prazo de entrega

ENTRY 139
Heading: 📦 Imile
Resposta:
Processo de Busca (Pedido em atraso) | Processo Acareção | Processo de Avaria | Alteração/Correção de Endereço | Devolução | Informações importantes

ENTRY 140
Heading: 📦 Imile
Resposta:
📄 Ver página completa da Imile

ENTRY 141
Heading: 📦 Transpen
Resposta:
Status: Aguardando

ENTRY 142
Heading: 📦 Transpen
Resposta:
Processo de Busca (Pedido em atraso) | Processo Acareção | Processo de Avaria | Alteração/Correção de Endereço | Devolução | Informações importantes

ENTRY 143
Heading: 📦 Transpen
Resposta:
📄 Ver página completa da Transpen

ENTRY 144
Heading: 📦 Sol Cargas
Resposta:
Status: Negociação

ENTRY 145
Heading: 📦 Sol Cargas
Resposta:
Processo de Busca (Pedido em atraso) | Processo Acareção | Processo de Avaria | Alteração/Correção de Endereço | Devolução | Informações importantes

ENTRY 146
Heading: 📦 Sol Cargas
Resposta:
📄 Ver página completa da Sol Cargas

ENTRY 147
Heading: 📦 Campinense
Resposta:
Status: Negociação

ENTRY 148
Heading: 📦 Campinense
Resposta:
Processo de Busca (Pedido em atraso) | Processo Acareção | Processo de Avaria

ENTRY 149
Heading: 📦 Campinense
Resposta:
📄 Ver página completa da Campinense

ENTRY 150
Heading: 📦 Campinense
Resposta:
Última revisão: Abril 2026 · Responsável: Supervisão Comercial

ENTRY 151
Heading: 🚚 Regras de Frete
Resposta:
A regra de frete grátis não funciona para uma cidade específica, mas funciona para outra.

ENTRY 152
Heading: 🚚 Regras de Frete
Resposta:
Isso acontece quando existem várias regras de frete para a mesma transportadora (por exemplo: uma regra de valor fixo e outra de frete grátis).

O sistema processa as regras em uma ordem específica. Se a regra de frete grátis roda antes da regra de valor fixo, o frete grátis é aplicado mas logo em seguida é sobrescrito pelo valor fixo.

Para resolver, entre em contato com o suporte técnico para que a equipe ajuste a ordem de prioridade das regras. A regra de frete grátis precisa ter a prioridade mais baixa para que rode por último e sobrescreva as demais.

ENTRY 153
Heading: 🚚 Regras de Frete
Resposta:
A regra de frete por SKU (código do produto) não está funcionando na integração Yampi.

ENTRY 154
Heading: 🚚 Regras de Frete
Resposta:
Esse problema foi identificado e corrigido. O conector da Yampi não estava enviando o código do produto (SKU) para o sistema de cotação, então as regras que dependiam do SKU não eram avaliadas.

A correção já está em produção. Se mesmo assim a regra não funcionar, verifique se o SKU cadastrado na regra de frete está exatamente igual ao SKU do produto na Yampi (incluindo maiúsculas, minúsculas e espaços).

ENTRY 155
Heading: 🚚 Regras de Frete
Pergunta: A regra de frete por cidade não está aplicando. O que pode ser?
Resposta:
As regras de frete por cidade funcionam com um código interno da cidade, não pelo nome. Quando você seleciona a cidade no painel, o sistema grava esse código automaticamente.

Se a regra não está funcionando para uma cidade específica:

1. Confira se a cidade foi selecionada corretamente ao criar a regra.
2. Teste com um CEP que pertença à cidade desejada.
3. Se ainda não funcionar, entre em contato com o suporte para verificar se existe conflito com outra regra de frete ativa.

ENTRY 156
Heading: 🐛 Bugs Conhecidos e Soluções
Pergunta: Recotei o pedido com um CEP diferente, mas o CEP antigo continua aparecendo no modal do destinatário. O que aconteceu?
Resposta:
Existe um bug conhecido onde, ao recotar um pedido (botão lápis na transportadora) com um CEP de destino diferente, o sistema troca a transportadora corretamente mas nem sempre salva o novo CEP na declaração de conteúdo. Por isso, ao abrir o modal do destinatário, o CEP antigo ainda aparece.

Como contornar: por enquanto, após recotar, abra o modal do destinatário (lápis no bloco de destino) e confira se o CEP atualizou. Se não atualizou, entre em contato com o suporte informando o número do pedido.

O time de tecnologia está trabalhando na correção. (Atualizado em 13/05/2026)

ENTRY 157
Heading: 🐛 Bugs Conhecidos e Soluções
Pergunta: A etiqueta integrada (com chave da NF-e) está saindo em duas páginas. Como resolver?
Resposta:
Quando a etiqueta de envio é gerada junto com a chave da NF-e (modo integrado), em alguns casos o conteúdo pode estourar o tamanho de uma única página 10x15cm, fazendo com que a impressão saia em duas folhas.

Isso já foi corrigido pela equipe de tecnologia. Se você ainda estiver enfrentando esse problema, verifique se está na versão mais recente do sistema. Caso persista, abra um ticket de suporte mencionando que a etiqueta integrada com DANFE está saindo em duas páginas.

Causa: logos, barcodes e espaçamentos internos ocupavam mais espaço que o disponível na página. A correção reduziu esses elementos e removeu margens extras do PDF. (Atualizado em 13/05/2026)

ENTRY 158
Heading: Rastreio da J&T não aparece ou não atualiza no sistema
Resposta:
Pergunta: O rastreio da J&T não está aparecendo ou os eventos não atualizam na plataforma SmartEnvios.

Resposta: Esse problema acontecia porque alguns eventos da J&T usavam códigos internos que o nosso sistema não entendia. Por exemplo: quando o pacote era devolvido ou tinha problema na entrega, esses eventos não apareciam.

Isso já foi corrigido (maio/2026). Agora todos os tipos de evento da J&T são importados corretamente.

Se você ainda vê rastreio desatualizado em pedidos antigos, eles vão atualizar conforme entrem na fila de reprocessamento. Pedidos novos já devem refletir normalmente.

Se o problema persistir com pedidos recentes, abra um chamado informando o número do pedido.

ENTRY 159
Heading: Erro ao carregar atendimentos no painel (erro 401)
Resposta:
Pergunta: Quando tento ver meus atendimentos na plataforma, aparece "Erro ao carregar atendimentos" com código 401.

Resposta: Esse erro significa que a sua sessão expirou ou os dados salvos no navegador ficaram desatualizados.

Para resolver:
1. Limpe os cookies e o cache do navegador
2. Faça logout e login novamente
3. Se não resolver, tente abrir em uma aba anônima (Ctrl+Shift+N no Chrome)

Se o erro continuar mesmo na aba anônima, abra um chamado para investigarmos.

ENTRY 160
Heading: Pedidos da Tray com CNPJ não integram automaticamente
Resposta:
Pergunta: Pedidos faturados para CNPJ na Tray não chegam automaticamente na plataforma SmartEnvios.

Resposta: Atualmente, alguns pedidos da Tray que são faturados para CNPJ podem não disparar o webhook corretamente, fazendo com que não sejam importados automaticamente.

Enquanto estamos trabalhando em uma correção, a solução é fazer o upload manual do XML da nota fiscal diretamente na plataforma SmartEnvios.

Se o problema acontecer com pedidos para CPF também, abra um chamado pois pode ser outra causa.

ENTRY 161
Heading: Status da Loggi não atualizam na plataforma
Resposta:
Pergunta: Os status dos pedidos da Loggi estão diferentes na plataforma SmartEnvios (ex: mostra pendente aqui mas entregue na Loggi).

Resposta: Esse problema foi corrigido com a atualização da integração Loggi V2 (maio/2026). Os novos eventos de rastreio da Loggi agora são importados corretamente.

Pedidos antigos que ficaram com status desatualizado podem precisar ser reprocessados. Pedidos novos já devem refletir os status corretos.

Se notar divergências em pedidos recentes, abra um chamado com os códigos de rastreio.

ENTRY 162
Heading: Erro ao criar logística reversa (falta de dados)
Resposta:
Pergunta: Ao tentar aprovar uma solicitação de logística reversa, o sistema retorna erro de falta de dados.

Resposta: Esse problema foi corrigido em maio/2026. As correções incluíram ajustes na inversão de remetente/destinatário e na validação de endereços.

Se o erro ainda aparecer, tente novamente. Se persistir, abra um chamado informando o número do pedido e a mensagem exata do erro.

ENTRY 163
Heading: Número do pedido VTEX aparece cortado (apenas últimos dígitos)
Resposta:
Pergunta: O número do pedido no painel mudou e agora mostra apenas os últimos dígitos em vez do número completo da VTEX.

Resposta: Identificamos uma alteração recente (08/05/2026) no conector VTEX que passou a enviar um código sequencial curto como identificador do pedido. A equipe de engenharia está trabalhando na correção para que o número completo volte a ser exibido. Os pedidos continuam funcionando normalmente — apenas a exibição do número foi afetada.

ENTRY 164
Heading: NF não aparece automaticamente no pedido (integração VTEX)
Resposta:
Pergunta: Emiti a nota fiscal mas ela não aparece no pedido na SmartEnvios para imprimir a etiqueta.

Resposta: Se você usa a integração VTEX, a nota fiscal precisa ser vinculada ao pedido na própria VTEX para que a SmartEnvios receba a informação. Verifique se a NF está corretamente associada ao pedido na VTEX. Se o problema persistir, é possível vincular a NF manualmente inserindo a chave de acesso no painel da SmartEnvios. A equipe técnica está trabalhando para melhorar a importação automática de NFs via VTEX.

ENTRY 165
Heading: NF do Bling não importa (limite de requisições da API)
Resposta:
Pergunta: As notas fiscais do Bling não estão sendo importadas automaticamente na SmartEnvios.

Resposta: O Bling tem um limite diário de requisições na API. Se você usa outras integrações ou aplicações que também consultam a API do Bling com o mesmo token, o limite pode ser atingido antes da SmartEnvios conseguir buscar as NFs. Para resolver: (1) Verifique se há outras aplicações usando o mesmo token do Bling e reduza o consumo. (2) Solicite ao Bling o aumento do limite diário. (3) Se você também tem integração com VTEX ou outra plataforma, considere migrar a importação de NFs para ela, pois não tem essa limitação.

ENTRY 166
Heading: Rastreio da JadLog não retorna informações
Resposta:
Pergunta: O rastreio dos meus pedidos via JadLog não mostra nenhuma informação no sistema.

Resposta: O rastreio da JadLog depende do código do pedido gerado pela própria JadLog no momento da criação da etiqueta. Se o rastreio não aparece, pode ser um atraso na atualização dos eventos pela JadLog — aguarde algumas horas e consulte novamente. Se após 24h o rastreio continuar sem informação, abra um ticket informando o código SM do pedido para que a equipe técnica verifique se o vínculo com a JadLog foi feito corretamente.

Importante: o rastreio JadLog NÃO usa código de rastreio externo como outras transportadoras. O sistema consulta diretamente a JadLog pelo código interno do pedido.

ENTRY 167
Heading: Pedido Gollog aparece como "não integrado" na plataforma
Resposta:
Pergunta: Meu pedido via Gollog não foi integrado na transportadora. O que aconteceu?

Resposta: A Gollog importa os pedidos com a nota fiscal fisicamente. Eles preenchem as informações manualmente no sistema deles junto com a carga. Por isso o pedido pode aparecer como "não integrado" na plataforma, mas já está sendo processado pela transportadora. Fale com a operação para confirmar o status da carga. Não é necessário abrir ticket para tecnologia neste caso.

ENTRY 168
Heading: Pedidos aparecendo duplicados na plataforma
Resposta:
Pergunta: Estão aparecendo pedidos duplicados na plataforma, o que pode ser?

Resposta: Isso geralmente acontece quando o embarcador tem mais de uma integração ativa com a mesma plataforma (ex: Bling). Cada integração importa os pedidos de forma independente, gerando duplicatas. Para resolver:
1. Verificar se existe mais de uma integração ativa na tela de integrações
2. Manter apenas uma e desativar/remover as demais
3. Não criar novas integrações quando der erro — entrar em contato com o suporte para reconectar a existente

Se já existem pedidos duplicados, será necessário que o time técnico faça a limpeza na base.

ENTRY 169
Heading: NF não importa automaticamente (Loja Integrada)
Resposta:
Pergunta: As notas fiscais não aparecem automaticamente nos pedidos da Loja Integrada.

Resposta: A integração com Loja Integrada importa apenas os dados do pedido, sem os dados da nota fiscal. A NF precisa ser vinculada separadamente. Opções:
1. Importação por email: configurar o email de NF-e no cadastro do embarcador (Configurações > Cadastro > Embarcadores > Processamento de NF). As notas enviadas por email serão importadas automaticamente.
2. Se usa Bling ou Tiny para emitir notas, verificar se a integração com esse ERP está ativa e funcionando.
3. Vincular manualmente pela plataforma.

ENTRY 170
Heading: Como cadastrar novos status de tracking?
Resposta:
Novos status de tracking podem ser cadastrados diretamente pela plataforma, sem necessidade de suporte técnico.

Caminho: Configurações → Cadastro → Status

IMPORTANTE: Antes de criar ou alterar status de tracking, é necessário alinhar com a gestão, pois alterações nesses status impactam toda a operação e relatórios.

