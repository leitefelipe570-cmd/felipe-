// supabase/functions/send-email/index.ts
// Edge Function para envio de emails pelo admin
// Deploy: supabase functions deploy send-email

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  // Verificar se é o admin
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  // Verificar usuário logado
  const token = authHeader.replace('Bearer ', '')
  const { data: { user }, error: authError } = await supabase.auth.getUser(token)
  if (authError || !user || user.email !== 'leitefelipe570@gmail.com') {
    return new Response(JSON.stringify({ error: 'Acesso negado' }), { status: 403 })
  }

  const body = await req.json()
  const { to, subject, html, type } = body

  if (!to || !subject || !html) {
    return new Response(JSON.stringify({ error: 'Campos obrigatórios: to, subject, html' }), { status: 400 })
  }

  // Enviar via Resend
  const resendRes = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      from: 'Suvita <onboarding@resend.dev>',
      to: Array.isArray(to) ? to : [to],
      subject,
      html
    })
  })

  const resendData = await resendRes.json()

  if (!resendRes.ok) {
    console.error('Resend error:', resendData)
    return new Response(JSON.stringify({ error: resendData }), { status: 500 })
  }

  console.log(`✅ Email enviado para ${to} — tipo: ${type || 'manual'}`)

  return new Response(
    JSON.stringify({ ok: true, id: resendData.id, to, subject }),
    { status: 200, headers: { 'Content-Type': 'application/json' } }
  )
})
