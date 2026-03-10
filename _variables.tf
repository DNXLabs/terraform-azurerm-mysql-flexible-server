variable "name" {
  description = "Resource name prefix used for all resources in this module."
  type        = string
}

variable "resource_group" {
  description = "Create or use an existing resource group."
  type = object({
    create   = bool
    name     = string
    location = optional(string)
  })
}

variable "tags" {
  description = "Extra tags merged with default tags."
  type        = map(string)
  default     = {}
}

variable "diagnostics" {
  description = "Optional Azure Monitor diagnostic settings."
  type = object({
    enabled                        = optional(bool, false)
    log_analytics_workspace_id     = optional(string)
    storage_account_id             = optional(string)
    eventhub_authorization_rule_id = optional(string)
  })
  default = {}
}

variable "mysql" {
  description = "MySQL Flexible Server configuration."
  type = object({
    name        = optional(string)

    sku_name = optional(string, "GP_Standard_D2ds_v4")
    version  = optional(string, "8.0.21")

    administrator_login    = string

    public_network_access = optional(string)

    backup_retention_days        = optional(number, 7)
    geo_redundant_backup_enabled = optional(bool, false)

    zone = optional(string)

    high_availability = optional(object({
      mode                      = string # SameZone | ZoneRedundant
      standby_availability_zone = optional(string)
    }))

    maintenance_window = optional(object({
      day_of_week  = number
      start_hour   = number
      start_minute = number
    }))

    storage = optional(object({
      size_gb           = optional(number, 20)
      iops              = optional(number, 360)
      auto_grow_enabled = optional(bool, true)
    }))
  })
}

variable "databases" {
  description = "Databases to create."
  type = list(object({
    name      = string
    charset   = optional(string, "utf8mb4")
    collation = optional(string, "utf8mb4_unicode_ci")
  }))
  default = []
}

variable "configurations" {
  description = "Server configurations (key/value)."
  type        = map(string)
  default     = {}
}

variable "private" {
  description = "Private Endpoint + Private DNS strategy."
  type = object({
    enabled = bool

    pe_subnet_id = optional(string)
    vnet_id      = optional(string)

    dns = optional(object({
      zone_name        = optional(string) # default: privatelink.mysql.database.azure.com
      create_zone      = optional(bool, true)
      create_vnet_link = optional(bool, true)

      resource_group = optional(object({
        create   = bool
        name     = string
        location = optional(string)
      }))
    }), {})
  })
}

variable "private_endpoint" {
  description = "Where the Private Endpoint should be created (RG/Location)."
  type = object({
    resource_group_name = string
    location            = string
  })
  default = {
    resource_group_name = null
    location            = null
  }
}

variable "administrator_password" {
  description = "MySQL administrator password."
  type        = string
  default     = null
  sensitive   = true
}
