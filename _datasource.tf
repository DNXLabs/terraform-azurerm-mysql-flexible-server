data "azurerm_resource_group" "existing" {
  count = var.resource_group.create ? 0 : 1
  name  = var.resource_group.name
}

# Only used when private enabled AND not creating the zone (reuse existing)
data "azurerm_private_dns_zone" "existing" {
  count               = (try(var.private.enabled, false) && try(var.private.dns.create_zone, true) == false) ? 1 : 0
  name                = coalesce(try(var.private.dns.zone_name, null), "privatelink.mysql.database.azure.com")
  resource_group_name = try(var.private.dns.resource_group.name, var.private_endpoint.resource_group_name)
}
