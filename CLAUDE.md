# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projeto

**Suvita — Suba na Vida** é um app de produtividade e finanças pessoais. Toda a aplicação vive em um único arquivo: `index.html`. Não há build, bundler, framework, nem dependências npm. O deploy é feito via Vercel (produção: `https://suvita-pi.vercel.app`).

## Como desenvolver

**Visualizar localmente:**
```bash
npx serve . -l 3000
# acesse http://localhost:3000/index.html
```

**Deploy:** qualquer push para o branch `main` no GitHub faz o deploy automático no Vercel.

**Arquivo de trabalho:** edite sempre `.claude/index.html`. Após salvar, copie para a raiz:
```bash
cp .claude/index.html index.html
```

## Arquitetura

O `index.html` é dividido em três blocos principais na seguinte ordem:

### 1. CSS (`<style>` — linhas ~11–467)
- **Design tokens** em `:root` — todas as cores, espaçamentos e fontes usam variáveis CSS (`--gold`, `--s1`…`--s4`, `--t1`…`--t3`, `--r`, `--r2`).
- Breakpoint mobile: `@media(max-width:767px)`. Abaixo disso, a sidebar fica oculta e abre via hambúrguer; acima de 767px a sidebar fica fixa à esquerda.
- Classes de página: `.pg` — todas as seções do app. A seção ativa recebe `.on` (`display:block`). Sem `.on` ficam `display:none`.

### 2. HTML (linhas ~468–1251)
Estrutura:
```
.shell
  .sidebar#sb          ← navegação desktop/mobile via hambúrguer
  .topbar              ← barra superior mobile com botão hambúrguer
  #scrim               ← overlay escuro quando sidebar mobile abre
  main.main
    #pg-dash           ← Dashboard
    #pg-metas
    #pg-tarefas
    #pg-rotina
    #pg-financeiro
    #pg-planilha
    #pg-analitico
    #pg-extrato        ← importação de extrato bancário (adicionado)
    #pg-historico
    #pg-planos
    #pg-auth           ← tela de login/cadastro
  .ov#ov-*             ← modais (overlays) para criar/editar registros
  #toast               ← notificações temporárias
```

### 3. JavaScript (`<script>` — linhas ~1251–fim)
Organizado em seções comentadas com `/* ══ NOME ══ */`:

| Seção | O que faz |
|---|---|
| `SUPABASE CONFIG` | `SUPA_URL`, `SUPA_KEY`, `initSupabase()` |
| `AUTH STATE` | `startAuthListener()`, `goApp()`, `showAuthPage()` |
| `USER PROFILE` | `loadUserProfile()`, `renderUserUI()`, `USER_PROFILE` |
| `SUPABASE DATA LAYER` | `dbLoad/dbInsert/dbUpdate/dbDelete`, `loadAllData()` |
| `STATE` | `var D` — objeto global com todos os dados em memória |
| `NAVIGATION` | `go(id)`, `NM` (sidebar map), `BM` (bottom nav map — mantido para compatibilidade) |
| `render*` | Uma função por seção: `renderDash`, `renderMetas`, `renderFin`, `renderAnalitico`, etc. |
| `EXTRATO` | `extProcessar()`, `extParsearTexto()`, `extParsearOFX()`, `extImportarSelecionados()` |

## Estado global

```js
var D = {
  metas:[], tarefas:[], trans:[], rot:[], lem:[],
  shApp:[], shRua:[], planilhas:[], shLinhas:[], historico:[]
}
```

- Persistido em `localStorage` com chave `sv3` via `save()`.
- Quando Supabase está configurado, `loadAllData()` sobrescreve o `D` com dados do banco após login.
- Sempre que mudar `D`, chame `save()` para persistir localmente.

## Supabase

- SDK carregado via CDN: `@supabase/supabase-js@2`
- Credenciais em `SUPA_URL` / `SUPA_KEY` (linhas ~1258–1259)
- Se `SUPA_URL` contiver `'COLE_'`, o app entra em **modo dev** (sem login, usa só localStorage)
- Tabelas: `metas`, `tarefas`, `rotina`, `lembretes`, `transacoes`, `user_planilhas`, `sh_linhas`, `historico_meses`, `planilha_app`, `planilha_rua`, `profiles`
- SQL de setup completo em `supabase_setup.sql`
- Toda query usa `eq('user_id', AUTH_USER.id)` — RLS habilitado em todas as tabelas

## Padrões internos

**Navegação:** sempre use `go('nome-da-pagina')` — atualiza `.pg.on`, destaque do nav e chama o `render*` correspondente. Ao adicionar nova página: (1) criar `<div class="pg" id="pg-NOME">`, (2) adicionar entrada em `NM`, (3) adicionar `else if` no `go()`, (4) adicionar `<div class="ni">` na sidebar.

**Modais:** use `.ov` + `.ov.on` (flex). Abrir: `openOv('ov-id')`. Fechar: `closeOv('ov-id')`. Clicar no backdrop fecha automaticamente.

**Toast:** `toast('mensagem')` — neutro | `toast('msg', 'ok')` — verde | `toast('msg', 'err')` — vermelho.

**Formatação de moeda:** `fR(valor)` retorna `"R$ 1.234,56"`.

**IDs locais:** `newId()` — gera id temporário `timestamp36 + random`. Substituído pelo UUID do Supabase após `dbInsert`.

**Cores por categoria:** use o objeto `CC` para cores de metas/tarefas e `TC` para tipos de transação financeira.

**Responsividade:** o breakpoint é 767px. Em mobile, a sidebar tem `transform: translateX(-100%)` e abre com a classe `.open` via `openSb()` / `closeSb()`.
