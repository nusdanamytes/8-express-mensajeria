export default async function handler(req,res) {
  res.setHeader("Cache-Control","no-store");
  if(req.method!=="POST"){res.setHeader("Allow","POST");return res.status(405).json({error:"Method not allowed."});}
  const url=process.env.VITE_SUPABASE_URL;
  const key=process.env.VITE_SUPABASE_PUBLISHABLE_KEY;
  const resendKey=process.env.RESEND_API_KEY;
  const from=process.env.RESEND_FROM_EMAIL;
  const token=String(req.headers.authorization||"").replace(/^Bearer\s+/i,"");
  if(!url||!key||!resendKey||!from)return res.status(503).json({error:"Email notifications are not configured. Add RESEND_API_KEY and RESEND_FROM_EMAIL to Vercel."});
  if(!token)return res.status(401).json({error:"Please sign in again."});
  try{
    const auth=await fetch(url.replace(/\/$/,"")+"/auth/v1/user",{headers:{apikey:key,Authorization:"Bearer "+token}});
    if(!auth.ok)return res.status(401).json({error:"Administrator session is invalid."});
    const user=await auth.json();
    if(user?.app_metadata?.role!=="admin")return res.status(403).json({error:"Administrator access is required."});
    const id=String(req.body?.shipmentId||"");
    const previous=String(req.body?.previousStatus||"");
    if(!id)return res.status(400).json({error:"Shipment reference is required."});
    const response=await fetch(url.replace(/\/$/,"")+"/rest/v1/shipments?id=eq."+encodeURIComponent(id)+"&select=tracking_number,receiver_name,receiver_email,status,current_location,latest_update,destination",{headers:{apikey:key,Authorization:"Bearer "+token}});
    if(!response.ok)return res.status(502).json({error:"Could not load shipment details."});
    const rows=await response.json();const s=rows?.[0];
    if(!s)return res.status(404).json({error:"Shipment not found."});
    if(s.status===previous)return res.status(200).json({message:"No status change; no email was sent."});
    if(!s.receiver_email)return res.status(200).json({message:"Shipment saved. No receiver email is recorded."});
    const safe=v=>String(v||"").replace(/[&<>"']/g,ch=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[ch]));
    const site=process.env.PUBLIC_SITE_URL||"https://8-express-mensajeria.vercel.app/";
    const subject="8 Express shipment update: "+s.tracking_number+" — "+s.status;
    const textBody=["Hello"+(s.receiver_name?" "+s.receiver_name:"")+",","","Your 8 Express shipment has a new status update.","Tracking number: "+s.tracking_number,"Status: "+s.status,"Current location: "+(s.current_location||"Update pending"),"Destination: "+(s.destination||"Not provided"),"Latest update: "+(s.latest_update||"No additional update provided."),"","Track your shipment: "+site,"","8 Express Mensajería y Paquetería"].join("\n");
    const html="<div style=\"font-family:Arial,sans-serif;line-height:1.6;max-width:600px;margin:auto;color:#14243a\"><h2 style=\"color:#071a33\">8 Express</h2><p>Hello "+(safe(s.receiver_name)||"Customer")+",</p><p>Your shipment has a new status update.</p><div style=\"background:#f4f6f9;padding:18px;border-radius:8px\"><p><b>Tracking:</b> "+safe(s.tracking_number)+"</p><p><b>Status:</b> "+safe(s.status)+"</p><p><b>Current location:</b> "+safe(s.current_location||"Update pending")+"</p><p><b>Destination:</b> "+safe(s.destination||"Not provided")+"</p><p><b>Latest update:</b> "+safe(s.latest_update||"No additional update provided.")+"</p></div><p><a href=\""+safe(site)+"\" style=\"display:inline-block;background:#f47721;color:white;padding:12px 18px;border-radius:5px;text-decoration:none\">Track shipment</a></p><p>Thank you for choosing 8 Express.</p></div>";
    const sent=await fetch("https://api.resend.com/emails",{method:"POST",headers:{Authorization:"Bearer "+resendKey,"Content-Type":"application/json"},body:JSON.stringify({from,to:[s.receiver_email],subject,text:textBody,html})});
    const result=await sent.json().catch(()=>({}));
    if(!sent.ok)return res.status(502).json({error:result?.message||"Email provider rejected the notification."});
    return res.status(200).json({message:"Shipment saved and notification sent to "+s.receiver_email+"."});
  }catch(e){return res.status(500).json({error:"Unexpected error sending shipment notification."});}
}
