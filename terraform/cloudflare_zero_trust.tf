locals {
  cloudflare_apps = var.enable_cloudflare_zero_trust ? {
    for app_name, app in var.cloudflare_tunnel_apps : app_name => {
      name                  = app_name
      subdomain             = trimspace(app.subdomain)
      hostname              = trimspace(app.subdomain) == "@" ? trimspace(var.cloudflare_domain) : "${trimspace(app.subdomain)}.${trimspace(var.cloudflare_domain)}"
      service               = trimspace(app.service)
      access_enabled        = app.access_enabled
      session_duration      = coalesce(app.session_duration, var.cloudflare_access_default_session_duration)
      app_launcher_visible  = app.app_launcher_visible
      allowed_emails        = app.allowed_emails
      allowed_email_domains = app.allowed_email_domains
    }
  } : {}

  cloudflare_access_apps = {
    for app_name, app in local.cloudflare_apps : app_name => app
    if app.access_enabled
  }

  cloudflare_tunnel_ingress = concat(
    [
      for _, app in local.cloudflare_apps : {
        hostname = app.hostname
        service  = app.service
      }
    ],
    [{ service = "http_status:404" }]
  )

  cloudflare_access_include_rules = {
    for app_name, app in local.cloudflare_access_apps : app_name => concat(
      [
        for email in app.allowed_emails : {
          email = {
            email = email
          }
        }
      ],
      [
        for domain in app.allowed_email_domains : {
          email_domain = {
            domain = domain
          }
        }
      ]
    )
  }

  cloudflare_access_identity_provider_id = var.enable_cloudflare_zero_trust ? trimspace(var.cloudflare_google_identity_provider_id) : null
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "shared" {
  count = var.enable_cloudflare_zero_trust ? 1 : 0

  account_id = var.cloudflare_account_id
  name       = var.cloudflare_tunnel_name
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "shared" {
  count = var.enable_cloudflare_zero_trust ? 1 : 0

  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.shared[0].id
  source     = "cloudflare"

  config = {
    ingress = local.cloudflare_tunnel_ingress
  }
}

resource "cloudflare_dns_record" "tunnel_apps" {
  for_each = local.cloudflare_apps

  zone_id = var.cloudflare_zone_id
  name    = each.value.subdomain
  type    = "CNAME"
  ttl     = 1
  content = "${cloudflare_zero_trust_tunnel_cloudflared.shared[0].id}.cfargotunnel.com"
  proxied = true
}

resource "cloudflare_zero_trust_access_policy" "allow" {
  for_each = local.cloudflare_access_apps

  account_id = var.cloudflare_account_id
  name       = "allow-access-${each.key}"
  decision   = "allow"
  include    = local.cloudflare_access_include_rules[each.key]
  require = [{
    login_method = {
      id = local.cloudflare_access_identity_provider_id
    }
  }]

  session_duration = each.value.session_duration
}

resource "cloudflare_zero_trust_access_application" "self_hosted" {
  for_each = local.cloudflare_access_apps

  zone_id = var.cloudflare_zone_id
  name    = "${title(replace(each.key, "_", " "))} (${each.value.hostname})"
  type    = "self_hosted"
  domain  = each.value.hostname
  policies = [{
    id         = cloudflare_zero_trust_access_policy.allow[each.key].id
    precedence = 1
  }]

  allowed_idps              = [local.cloudflare_access_identity_provider_id]
  app_launcher_visible      = each.value.app_launcher_visible
  auto_redirect_to_identity = true
  session_duration          = each.value.session_duration
}

output "cloudflare_tunnel_id" {
  description = "Cloudflare tunnel UUID"
  value       = try(cloudflare_zero_trust_tunnel_cloudflared.shared[0].id, null)
}

output "cloudflare_tunnel_cname_target" {
  description = "CNAME target for tunnel-routed hostnames"
  value       = try("${cloudflare_zero_trust_tunnel_cloudflared.shared[0].id}.cfargotunnel.com", null)
}

output "cloudflare_app_hostnames" {
  description = "Resolved hostname for each tunnel app key"
  value = {
    for app_name, app in local.cloudflare_apps : app_name => app.hostname
  }
}

output "cloudflare_access_application_ids" {
  description = "Access application IDs keyed by tunnel app name"
  value = {
    for app_name, app in cloudflare_zero_trust_access_application.self_hosted : app_name => app.id
  }
}

output "cloudflare_access_identity_provider_id" {
  description = "Google Access login method ID used by Terraform-managed apps"
  value       = local.cloudflare_access_identity_provider_id
}
