output "mysql" {
  description = "MySQL Flexible Server resource."
  value       = azurerm_mysql_flexible_server.this
}

output "id" {
  value = azurerm_mysql_flexible_server.this.id
}

output "name" {
  value = azurerm_mysql_flexible_server.this.name
}

output "fqdn" {
  value = azurerm_mysql_flexible_server.this.fqdn
}

output "resource_group_name" {
  value = azurerm_mysql_flexible_server.this.resource_group_name
}

output "private" {
  value = local.private_enabled ? {
    private_endpoint_id     = try(azurerm_private_endpoint.this["this"].id, null)
    private_dns_zone_name   = local.dns_zone_name
    private_dns_zone_id     = local.private_dns_zone_id
    vnet_link_name          = try(azurerm_private_dns_zone_virtual_network_link.this["this"].name, null)
  } : null
}
