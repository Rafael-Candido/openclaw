# Repositórios GitHub Locais (SmartEnvios)

Inventário gerado em: 2026-02-20 21:35:32
Total de repositórios: 10

> **Nota:** Estes são repositórios locais encontrados em `/var/www/ms.*`

---

## 📊 Sumário por Tecnologia

- **React:** 10 repositórios
- **Node.js:** 10 repositórios
- **Docker:** 8 repositórios
- **TypeScript:** 8 repositórios
- **NestJS:** 6 repositórios
- **Jest:** 6 repositórios
- **Knex:** 3 repositórios
- **Next.js:** 1 repositórios
- **Prisma:** 1 repositórios

---

## 🗂️ Detalhes dos Repositórios

### 1. ms.notifications

**Caminho:** `/var/www/ms.notifications`

**Status Git:** ✅ Repositório Git
**Branch atual:** `block-duplicated-message`
**Remote URL:** https://github.com/SmartEnvios/ms.notifications.git
**Último commit:** `36e50e5b` - solved (lint 2026-02-19)

**Descrição:** # ms.notifications - Microserviço de Notificações ## Visão Geral O `ms.notifications` é um serviço desacoplado e escalável, construído para gerenciar e persistir notificações destinadas aos clientes da plataforma. O serviço opera de forma assíncrona, recebendo eventos de outros microsserviços, armazenando-os de forma durável e notificando os clientes em tempo real através de WebSocket.

**Tecnologias:** NestJS, Docker, React, Jest, Node.js, TypeScript

**Arquivos importantes:**
- `CHANGELOG.md`
- `nest-cli.json`
- `README.md`
- `package-lock.json`
- `package.json`
- `tsconfig.build.json`
- `tsconfig.json`
- `jest.config.ts`
- `test/phone-variants.spec.ts`
- `test/notifications.e2e-spec.ts`
- ... (mais arquivos)

---

### 2. ms.points

**Caminho:** `/var/www/ms.points`

**Status Git:** ✅ Repositório Git
**Branch atual:** `implement_externls`
**Remote URL:** git@github.com:SmartEnvios/ms.points.git
**Último commit:** `f095e5e3` - sugest (codex 2026-01-28)

**Descrição:** # ms.points ## Autenticação All requests except `/api/login` require an `Authorization` header with a valid token:

**Tecnologias:** Knex, React, Node.js, Docker

**Arquivos importantes:**
- `swagger.yaml`
- `knexfile.js`
- `README.md`
- `package-lock.json`
- `package.json`
- `migrations/20241008100000_create_point_freight_order_items.js`
- `.github/workflows/buildDevRelease.yaml`
- `.github/workflows/buildNewRelease.yaml`
- `.github/workflows/deployRelease.yaml`
- `src/app.js`
- ... (mais arquivos)

---

### 3. ms.ticket-generator

**Caminho:** `/var/www/ms.ticket-generator`

**Status Git:** ✅ Repositório Git
**Branch atual:** `tracking-codes-print-label`
**Remote URL:** https://github.com/SmartEnvios/ms.ticket-generator.git
**Último commit:** `e17ef3a8` - v1.27.37 (2025-12-04)

**Descrição:** # Ticket Generator Serviço responsável por gerar etiquetas do pedidos e integrar etiquetas com transportadoras. Mais sobre esse microserviço: [Docs ⇗](./docs/intro.mdx)

**Tecnologias:** Knex, React, Node.js, Docker

**Arquivos importantes:**
- `jsconfig.json`
- `knexfile.js`
- `README.md`
- `prettier.config.js`
- `package-lock.json`
- `package.json`
- `.eslintrc.json`
- `test/stubs/ticket-order.stub.js`
- `test/stubs/ticket-destiny-city-zip-code.stub.js`
- `test/stubs/ticket-orders-filter-transporter.stub.js`
- ... (mais arquivos)

---

### 4. ms.crm

**Caminho:** `/var/www/ms.crm`

**Status Git:** ✅ Repositório Git
**Branch atual:** `middleware-persons`
**Remote URL:** https://github.com/SmartEnvios/ms.crm.git
**Último commit:** `52cb5e7e` - implement (middleware 2025-11-17)

**Descrição:** # CRM SmartEnvios Sistema CRM moderno e otimizado para gestão de franquias, desenvolvido com React, TypeScript e Tailwind CSS. ## 🚀 Funcionalidades

**Tecnologias:** Next.js, React, Node.js, TypeScript

**Arquivos importantes:**
- `tsconfig.node.json`
- `tailwind.config.js`
- `next.config.js`
- `next-env.d.ts`
- `README.md`
- `package-lock.json`
- `package.json`
- `tsconfig.json`
- `postcss.config.js`
- `.eslintrc.json`
- ... (mais arquivos)

---

### 5. ms.expedition-hub

**Caminho:** `/var/www/ms.expedition-hub`

**Status Git:** ✅ Repositório Git
**Branch atual:** `develop`
**Remote URL:** https://github.com/SmartEnvios/ms.expedition-hub.git
**Último commit:** `b05db5f4` - feat: (SME-14084 Integração com 99 na finalização do romaneio 2025-12-03)

**Descrição:** # Microservice Expedition Hub O microserviço de hub tem por finalidade realizar gestão, logística e transporte de volumes, e gerenciar as empresas e pessoas envolvidas durante o processo

**Tecnologias:** NestJS, Docker, React, Node.js, TypeScript

**Arquivos importantes:**
- `nest-cli.json`
- `README.md`
- `package-lock.json`
- `package.json`
- `tsconfig.build.json`
- `tsconfig.json`
- `docker-compose.yml`
- `test/jest-e2e.json`
- `dist/main.d.ts`
- `dist/main.js`
- ... (mais arquivos)

---

### 6. ms.zardbank

**Caminho:** `/var/www/ms.zardbank`

**Status Git:** ✅ Repositório Git
**Branch atual:** `main`
**Remote URL:** https://github.com/SmartEnvios/ms.zardbank.git
**Último commit:** `01a84959` - Merge (pull request #586 from SmartEnvios/develop 2026-02-03)

**Descrição:** # Zardbank

**Tecnologias:** NestJS, Docker, React, Jest, Node.js, TypeScript

**Arquivos importantes:**
- `nest-cli.json`
- `typeorm.config.ts`
- `pull_request_template.md`
- `README.md`
- `package.json`
- `tsconfig.build.json`
- `tsconfig.json`
- `jest.config.ts`
- `database/migrations/1719077296960-AddNumberToFrieghtOrderTicket.ts`
- `database/migrations/1720531407079-add-new-payment-columns-to-invoice.ts`
- ... (mais arquivos)

---

### 7. ms.label-processor

**Caminho:** `/var/www/ms.label-processor`

**Status Git:** ✅ Repositório Git
**Branch atual:** `main`
**Remote URL:** https://github.com/SmartEnvios/ms.label-processor.git
**Último commit:** `f81019a9` - Merge (pull request #136 from SmartEnvios/develop 2026-01-23)

**Descrição:** # Documentação ## Verificando a saúde do worker em ambiente Kubernetes O worker SQS utiliza uma abordagem baseada em arquivo para verificação de saúde (health check), evitando a necessidade de um servidor HTTP completo. Isso torna a aplicação mais leve e focada em sua função principal de processamento de mensagens.

**Tecnologias:** NestJS, Docker, React, Jest, Node.js, TypeScript

**Arquivos importantes:**
- `CHANGELOG.md`
- `nest-cli.json`
- `pull_request_template.md`
- `README.md`
- `package-lock.json`
- `package.json`
- `tsconfig.build.json`
- `tsconfig.json`
- `jest.config.ts`
- `test/setup-env.ts`
- ... (mais arquivos)

---

### 8. ms.connectors

**Caminho:** `/var/www/ms.connectors`

**Status Git:** ✅ Repositório Git
**Branch atual:** `improve-dhl-quote`
**Remote URL:** https://github.com/SmartEnvios/ms.connectors.git
**Último commit:** `6ec437ab` - adjusted-recomendation-bot (2026-02-18)

**Descrição:** # Ms.Connectors > Software de controle das plataformas integradoras da SmartEnvios.

**Tecnologias:** NestJS, Docker, React, Jest, Node.js, TypeScript

**Arquivos importantes:**
- `changelog.md`
- `nest-cli.json`
- `jest.config.js`
- `pull_request_template.md`
- `README.md`
- `package-lock.json`
- `package.json`
- `tsconfig.build.json`
- `.eslintrc.js`
- `tsconfig.json`
- ... (mais arquivos)

---

### 9. ms.customer-service

**Caminho:** `/var/www/ms.customer-service`

**Status Git:** ✅ Repositório Git
**Branch atual:** `init`
**Remote URL:** https://github.com/SmartEnvios/ms.customer-service.git
**Último commit:** `8c2ad3ce` - refactor(tenant): (padronizar escopo branding nos cadastros 2026-02-07)

**Descrição:** # ms.customer-service Central de Atendimento white-label, multi-tenant e omnichannel da SmartEnvios. ## Documentação

**Tecnologias:** NestJS, React, Jest, Node.js, Prisma, TypeScript

**Arquivos importantes:**
- `nest-cli.json`
- `jest.config.js`
- `README.md`
- `package-lock.json`
- `package.json`
- `tsconfig.json`
- `dist/app.module.d.ts`
- `dist/main.d.ts`
- `dist/app.controller.js`
- `dist/main.js`
- ... (mais arquivos)

---

### 10. ms.atendimento

**Caminho:** `/var/www/ms.atendimento`

**Status Git:** ✅ Repositório Git
**Branch atual:** `main`
**Remote URL:** https://github.com/SmartEnvios/ms.atendimento.git
**Último commit:** `3fa84a55` - Merge (pull request #61 from SmartEnvios/feat/smart-atendimentos-full-updates 2026-02-06)

**Descrição:** # Smart Atendimentos API Backend API RESTful para gerenciamento de tickets integrado com Zendesk. ## 📋 Índice

**Tecnologias:** Docker, Jest, React, Knex, Node.js, TypeScript

**Arquivos importantes:**
- `ZENDESK_SYNC.md`
- `OTIMIZACAO_TICKET_INDIVIDUAL.md`
- `ARQUITETURA.md`
- `jest.config.js`
- `OTIMIZACOES_PERFORMANCE.md`
- `README.md`
- `package-lock.json`
- `package.json`
- `DOCUMENTATION.md`
- `tsconfig.json`
- ... (mais arquivos)

---

