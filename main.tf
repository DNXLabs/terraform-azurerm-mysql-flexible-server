resource "azurerm_resource_group" "this" {
  for_each = var.resource_group.create ? { "this" = var.resource_group } : {}
  name     = each.value.name
  location = each.value.location
  tags     = local.tags
}

resource "azurerm_resource_group" "dns" {
  for_each = local.dns_rg_create ? { "this" = true } : {}
  name     = local.dns_rg_name
  location = local.dns_rg_loc
  tags     = local.tags
}

resource "azurerm_private_dns_zone" "this" {
  for_each            = (local.private_enabled && local.dns_create_zone) ? { "this" = true } : {}
  name                = local.dns_zone_name
  resource_group_name = local.dns_rg_name
  tags                = local.tags

  depends_on = [azurerm_resource_group.dns]
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each              = (local.private_enabled && local.dns_create_vnet_link) ? { "this" = true } : {}
  name                  = local.vnet_link_name
  resource_group_name   = local.dns_rg_name
  private_dns_zone_name = local.dns_zone_name
  virtual_network_id    = local.vnet_id
  tags                  = local.tags

  depends_on = [azurerm_private_dns_zone.this]
}

resource "azurerm_mysql_flexible_server" "this" {
  name                = local.mysql_name
  location            = local.rg_loc
  resource_group_name = local.rg_name

  administrator_login    = var.mysql.administrator_login
  administrator_password = var.administrator_password

  public_network_access = try(var.mysql.public_network_access, "Disabled")

  sku_name = try(var.mysql.sku_name, "GP_Standard_D2ds_v4")
  version  = try(var.mysql.version, "8.0.21")

  backup_retention_days        = try(var.mysql.backup_retention_days, 7)
  geo_redundant_backup_enabled = try(var.mysql.geo_redundant_backup_enabled, false)

  dynamic "high_availability" {
    for_each = try(var.mysql.high_availability, null) != null ? [var.mysql.high_availability] : []
    content {
      mode                      = high_availability.value.mode
      standby_availability_zone = try(high_availability.value.standby_availability_zone, null)
    }
  }

  dynamic "maintenance_window" {
    for_each = try(var.mysql.maintenance_window, null) != null ? [var.mysql.maintenance_window] : []
    content {
      day_of_week  = maintenance_window.value.day_of_week
      start_hour   = maintenance_window.value.start_hour
      start_minute = maintenance_window.value.start_minute
    }
  }

  dynamic "storage" {
    for_each = try(var.mysql.storage, null) != null ? [var.mysql.storage] : []
    content {
      size_gb           = try(storage.value.size_gb, 20)
      iops              = try(storage.value.iops, 360)
      auto_grow_enabled = try(storage.value.auto_grow_enabled, true)
    }
  }

  zone = try(var.mysql.zone, null)

  tags = local.tags
}

# Private Endpoint for MySQL Flexible Server
resource "azurerm_private_endpoint" "this" {
  for_each            = local.private_enabled ? { "this" = true } : {}
  name                = local.pe_name
  location            = local.pe_loc
  resource_group_name = local.pe_rg_name
  subnet_id                     = local.pe_subnet_id
  custom_network_interface_name = local.nic_name
  tags                          = local.tags

  private_service_connection {
    name                           = local.psc_name
    private_connection_resource_id = azurerm_mysql_flexible_server.this.id
    is_manual_connection           = false

    # Azure doc table: MySQL Flexible Server uses subresource mysqlServer
    subresource_names = ["mysqlServer"]
  }

  # This is what makes DNS records appear automatically in the Private DNS zone
  private_dns_zone_group {
    name                 = "pdzg-mysql-${local.prefix}"
    private_dns_zone_ids = [local.private_dns_zone_id]
  }

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.this
  ]
}

resource "azurerm_mysql_flexible_database" "this" {
  for_each = { for d in try(var.databases, []) : d.name => d }

  name                = each.value.name
  resource_group_name = local.rg_name
  server_name         = azurerm_mysql_flexible_server.this.name

  charset   = try(each.value.charset, "utf8mb4")
  collation = try(each.value.collation, "utf8mb4_unicode_ci")
}

resource "azurerm_mysql_flexible_server_configuration" "this" {
  for_each = (var.configurations == null) ? {} : var.configurations

  name                = each.key
  resource_group_name = local.rg_name
  server_name         = azurerm_mysql_flexible_server.this.name
  value               = each.value
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = local.diag_enabled ? { "this" = true } : {}

  name                           = "diag-${local.mysql_name}"
  target_resource_id             = azurerm_mysql_flexible_server.this.id
  log_analytics_workspace_id     = try(var.diagnostics.log_analytics_workspace_id, null)
  storage_account_id             = try(var.diagnostics.storage_account_id, null)
  eventhub_authorization_rule_id = try(var.diagnostics.eventhub_authorization_rule_id, null)

  enabled_log { category = "MySqlAuditLogs" }
  enabled_log { category = "MySqlSlowLogs" }

  enabled_metric {
    category = "AllMetrics"
  }
}
