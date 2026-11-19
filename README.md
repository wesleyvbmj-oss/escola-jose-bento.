# Sistema Escolar — publicação no Vercel + Supabase

## Arquivos
- `index.html`: site da escola com autenticação, reservas, estoque e painel.
- `config.js`: URL e chave pública do projeto Supabase.
- `supabase_setup.sql`: tabelas, políticas RLS, função segura de reserva e estoque inicial.
- `vercel.json`: configuração simples de hospedagem estática.

## 1. Preparar o Supabase
1. Crie um projeto em https://supabase.com/dashboard.
2. Abra SQL Editor → New query.
3. Cole todo o conteúdo de `supabase_setup.sql` e execute.
4. Abra Project Settings → API (ou API Keys) e copie Project URL e a chave pública `anon`/`publishable`.
5. Cole esses dois valores em `config.js`. Nunca use `service_role` ou secret key no navegador.

## 2. Criar o primeiro administrador
1. Publique o site e crie a conta da direção pela tela Criar conta.
2. Confirme o e-mail se a confirmação estiver habilitada.
3. No Supabase, abra SQL Editor e execute, substituindo pelo e-mail real:
   `update public.profiles set role = 'admin' where email = 'direcao@escola.com';`
4. Saia e entre novamente no site. O painel de usuários e a gestão do estoque ficarão disponíveis.

A senha antiga de demonstração `ADM 22` não é usada. A administração é definida pelo banco, não por uma senha escrita no JavaScript. Não existe cadastro público de administrador.

## 3. Como cadastrar professores e coordenadores
- Enquanto o cadastro estiver habilitado, professores podem criar a própria conta; a função inicial é sempre `professor`.
- Um administrador altera a função para `coordinator` ou `admin` no menu Usuários.
- Para convites controlados, use Supabase Dashboard → Authentication → Users → Add user / Invite user.
- Depois que todos tiverem conta, a direção pode desativar o cadastro público em Authentication → Settings.

## 4. Publicar no Vercel
1. Crie uma conta em https://vercel.com/.
2. Crie um repositório no GitHub e envie os quatro arquivos desta pasta.
3. No Vercel, escolha Add New → Project e importe o repositório.
4. Framework Preset: Other. Build Command e Output Directory podem ficar vazios (ou Output Directory `.`).
5. Clique Deploy. O endereço `*.vercel.app` será criado automaticamente.

## Observações importantes
- A reserva é confirmada por uma função SQL transacional, que verifica o estoque e evita duas confirmações simultâneas para as últimas unidades.
- As tabelas usam Row Level Security (RLS). O navegador recebe somente a chave pública; permissões são verificadas no banco.
- A disponibilidade depende de datas/horários e reservas confirmadas.
- Antes de usar com dados reais de estudantes, a direção deve validar a política de privacidade, o controle de acesso e os requisitos da LGPD.
