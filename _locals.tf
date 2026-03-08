locals {
  prefix = var.name

  default_tags = {
    name      = var.name
    managedBy = "terraform"
  }

  tags = merge(local.default_tags, var.tags)

  rg_name = var.resource_group.create ? azurerm_resource_group.this["this"].name : data.azurerm_resource_group.existing[0].name
  rg_loc  = var.resource_group.create ? azurerm_resource_group.this["this"].location : (try(var.resource_group.location, null) != null ? var.resource_group.location : data.azurerm_resource_group.existing[0].location)

  # MySQL server name rules: lowercase letters, numbers, hyphen; <= 63 chars
  base_mysql_name_raw = "mysql-${local.prefix}-${try(var.mysql.name_suffix, "001")}"
  base_mysql_name     = substr(replace(lower(local.base_mysql_name_raw), "/[^0-9a-z-]/", "-"), 0, 63)
  mysql_name          = coalesce(try(var.mysql.name, null), local.base_mysql_name)

  private_enabled = try(var.private.enabled, false)

  pe_subnet_id = local.private_enabled ? try(var.private.pe_subnet_id, null) : null
  vnet_id      = local.private_enabled ? try(var.private.vnet_id, null) : null

  pe_rg_name = coalesce(try(var.private_endpoint.resource_group_name, null), local.rg_name)
  pe_loc     = coalesce(try(var.private_endpoint.location, null), local.rg_loc)

  dns_cfg = try(var.private.dns, {})

  dns_rg_create = local.private_enabled && try(local.dns_cfg.resource_group.create, false)

  dns_rg_name = coalesce(
    try(local.dns_cfg.resource_group.name, null),
    local.pe_rg_name
  )

  dns_rg_loc = coalesce(
    try(local.dns_cfg.resource_group.location, null),
    local.pe_loc
  )

  # Standardized Private Endpoint DNS zone (per Azure private endpoint DNS documentation)
  dns_zone_name = coalesce(
    try(local.dns_cfg.zone_name, null),
    "privatelink.mysql.database.azure.com"
  )

  dns_create_zone      = local.private_enabled && try(local.dns_cfg.create_zone, true)
  dns_create_vnet_link = local.private_enabled && try(local.dns_cfg.create_vnet_link, true)

  private_dns_zone_id = local.private_enabled ? (
    local.dns_create_zone
    ? azurerm_private_dns_zone.this["this"].id
    : data.azurerm_private_dns_zone.existing[0].id
  ) : null

  pe_name   = "pe-mysql-${local.mysql_name}"
  psc_name  = "psc-mysql-${local.mysql_name}"
  nic_name  = "nic-pe-mysql-${local.mysql_name}"

  vnet_link_name = "link-${local.prefix}-mysql"

  diag_enabled = try(var.diagnostics.enabled, false) && (try(var.diagnostics.log_analytics_workspace_id, null) != null || try(var.diagnostics.storage_account_id, null) != null || try(var.diagnostics.eventhub_authorization_rule_id, null) != null)
}
