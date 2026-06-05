// supabase/functions/kiwify-webhook/index.ts
// Deploy: supabase functions deploy kiwify-webhook
//
// Este webhook é chamado automaticamente pela Kiwify quando:
// - Alguém assina o plano Pro (order_approved / subscription_active)
// - Assinatura é cancelada (subscription_cancelled / refunded)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req: Request) => {
  // Aceitar apenas POST
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  let body: any
  try {
    body = await req.json()
  } catch {
    return new Response('Invalid JSON', { status: 400 })
  }

  // Extrair e-mail do cliente (Kiwify envia em diferentes campos)
  const email = (
    body?.Customer?.email ||
    body?.customer?.email ||
    body?.buyer?.email ||
    body?.email ||
    ''
  ).trim().toLowerCase()

  if (!email) {
    console.error('Webhook recebido sem e-mail:', JSON.stringify(body))
    return new Response(JSON.stringify({ error: 'email not found' }), { status: 400 })
  }

  // Determinar o evento
  const event = (
    body?.status ||
    body?.event ||
    body?.order_status ||
    ''
  ).toLowerCase()

  console.log(`Kiwify webhook → email: ${email}, event: ${event}`)

  // Eventos que ATIVAM o Pro
  const eventosAtivos = [
    'paid', 'approved', 'active', 'complete', 'completed',
    'order_approved', 'subscription_active', 'subscription_paid'
  ]

  // Eventos que REMOVEM o Pro
  const eventosCancelados = [
    'cancelled', 'canceled', 'refunded', 'chargeback',
    'subscription_cancelled', 'subscription_canceled', 'expired'
  ]

  const isAtivo     = eventosAtivos.some(e => event.includes(e))
  const isCancelado = eventosCancelados.some(e => event.includes(e))

  if (!isAtivo && !isCancelado) {
    // Evento desconhecido — logar e ignorar
    console.warn(`Evento desconhecido: ${event}`)
    return new Response(JSON.stringify({ ok: true, ignored: true, event }), { status: 200 })
  }

  // Inicializar Supabase com Service Role (acesso admin)
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  // Buscar usuário pelo e-mail na tabela auth.users
  const { data: usersData, error: usersError } = await supabase.auth.admin.listUsers()
  if (usersError) {
    console.error('Erro ao listar usuários:', usersError.message)
    return new Response(JSON.stringify({ error: usersError.message }), { status: 500 })
  }

  const user = usersData?.users?.find(u => u.email?.toLowerCase() === email)

  if (!user) {
    // Usuário ainda não tem conta no Suvita
    console.warn(`Usuário não encontrado para e-mail: ${email}`)
    return new Response(
      JSON.stringify({ error: 'user not found', email }),
      { status: 404 }
    )
  }

  // Atualizar plano no profiles
  const novoPlano = isAtivo ? 'pro' : 'gratuito'
  const update: any = {
    plano: novoPlano,
    pro_since: isAtivo ? new Date().toISOString() : null
  }

  const { error: updateError } = await supabase
    .from('profiles')
    .update(update)
    .eq('id', user.id)

  if (updateError) {
    console.error('Erro ao atualizar perfil:', updateError.message)
    return new Response(JSON.stringify({ error: updateError.message }), { status: 500 })
  }

  console.log(`✅ Plano atualizado: ${email} → ${novoPlano}`)

  return new Response(
    JSON.stringify({ ok: true, email, plano: novoPlano, event }),
    {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    }
  )
})
