# terraform-azurerm-mysql-flexible-server

Terraform module for creating and managing Azure Database for MySQL Flexible Servers with support for databases, server configurations, private endpoints with automatic DNS zone management, and high availability.

This module provides enterprise-grade MySQL deployments with configurable storage, backup retention, and secure connectivity through private endpoints.

## Features

- **MySQL Flexible Server**: Create production-ready MySQL 8.0 instances
- **Multiple Databases**: Create and manage multiple databases with custom charset/collation
- **Server Configurations**: Apply custom MySQL server parameters
- **High Availability**: Same-zone or zone-redundant HA configurations
- **Storage Management**: Configurable IOPS, auto-grow, and storage size
- **Maintenance Windows**: Schedule maintenance during preferred windows
- **Private Endpoints**: Automatic private endpoint creation with DNS zones
- **Private DNS Zones**: Automatic creation and management of private DNS zones
- **Diagnostic Settings**: Optional Azure Monitor integration (Log Analytics, Storage, Event Hub)
- **Resource Group Flexibility**: Create new or use existing resource groups
- **Tagging Strategy**: Built-in default tagging with custom tag support

## Usage

### Example 1 — Non-Prod (Public Access, Basic Config)

A simple MySQL server for development/testing with public access enabled.

```hcl
module "mysql" {
  source = "./modules/mysql"

  name = "mycompany-dev-aue-app"

  resource_group = {
    create   = true
    name     = "rg-mycompany-dev-aue-app-001"
    location = "australiaeast"
  }

  tags = {
    project     = "my-app"
    environment = "development"
  }

  mysql = {
    sku_name               = "B_Standard_B1ms"
    version                = "8.0.21"
    administrator_login    = "mysqladmin"
    public_network_access  = "Enabled"
    backup_retention_days  = 7

    storage = {
      size_gb           = 20
      auto_grow_enabled = true
    }
  }

  administrator_password = var.mysql_password  # From password module or variable

  databases = [
    {
      name = "appdb"
    }
  ]

  private = {
    enabled = false
  }
}
```

### Example 2 — Production (Private, HA, Custom Config)

A production MySQL server with high availability, private endpoints, and custom configurations.

```hcl
module "mysql" {
  source = "./modules/mysql"

  name = "contoso-prod-aue-data"

  resource_group = {
    create   = true
    name     = "rg-contoso-prod-aue-data-001"
    location = "australiaeast"
  }

  tags = {
    project     = "data-platform"
    environment = "production"
    compliance  = "pci-dss"
  }

  mysql = {
    sku_name              = "GP_Standard_D4ds_v4"
    version               = "8.0.21"
    administrator_login   = "mysqladmin"
    public_network_access = "Disabled"

    backup_retention_days        = 35
    geo_redundant_backup_enabled = true

    zone = "1"

    high_availability = {
      mode                      = "ZoneRedundant"
      standby_availability_zone = "2"
    }

    maintenance_window = {
      day_of_week  = 0  # Sunday
      start_hour   = 2
      start_minute = 0
    }

    storage = {
      size_gb           = 256
      iops              = 700
      auto_grow_enabled = true
    }
  }

  administrator_password = module.mysql_password.value

  databases = [
    {
      name      = "app_production"
      charset   = "utf8mb4"
      collation = "utf8mb4_unicode_ci"
    },
    {
      name      = "app_analytics"
      charset   = "utf8mb4"
      collation = "utf8mb4_unicode_ci"
    }
  ]

  configurations = {
    "max_connections"       = "500"
    "innodb_buffer_pool_size" = "2147483648"
    "slow_query_log"        = "ON"
    "long_query_time"       = "2"
  }

  private = {
    enabled = true

    pe_subnet_id = "/subscriptions/xxxx/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-pe"
    vnet_id      = "/subscriptions/xxxx/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-prod"

    dns = {
      create_zone      = true
      create_vnet_link = true

      resource_group = {
        create = false
        name   = "rg-contoso-prod-aue-dns-001"
      }
    }
  }

  private_endpoint = {
    resource_group_name = "rg-contoso-prod-aue-network-001"
    location            = "australiaeast"
  }

  diagnostics = {
    enabled                    = true
    log_analytics_workspace_id = "/subscriptions/xxxx/resourceGroups/rg-monitor/providers/Microsoft.OperationalInsights/workspaces/law-prod"
  }
}
```

### Using YAML Variables

Create a `vars/identity.yaml` file:

```yaml
azure:
  subscription_id: "afb35bd4-145f-4a15-889e-5da052d030ce"
  location: australiaeast

network_lookup:
  resource_group_name: "rg-managed-services-lab-aue-stg-001"
  vnet_name: "vnet-managed-services-lab-aue-stg-001"
  pe_subnet_name: "snet-stg-pe"

identity:
  mysql_servers:
    main:
      naming:
        org: managed-services
        env: lab
        region: aue
        workload: stg

      resource_group:
        create: false
        name: rg-managed-services-lab-aue-stg-001
        location: australiaeast

      mysql:
        sku_name: GP_Standard_D2ds_v4
        version: "8.0.21"
        administrator_login: mysqladmin
        public_network_access: Disabled
        backup_retention_days: 7

        storage:
          size_gb: 20
          iops: 360
          auto_grow_enabled: true

      databases:
        - name: appdb
          charset: utf8mb4
          collation: utf8mb4_unicode_ci

      configurations:
        max_connections: "200"

      private:
        enabled: true
        dns:
          create_zone: true
          create_vnet_link: true
          resource_group:
            create: true
            name: "rg-dns-services-lab-aue-001"
            location: australiaeast
```

Then use in your Terraform:

```hcl
locals {
  workspace = yamldecode(file("vars/${terraform.workspace}.yaml"))
}

data "azurerm_resource_group" "network" {
  name = local.workspace.network_lookup.resource_group_name
}

data "azurerm_virtual_network" "this" {
  name                = local.workspace.network_lookup.vnet_name
  resource_group_name = data.azurerm_resource_group.network.name
}

data "azurerm_subnet" "pe" {
  name                 = local.workspace.network_lookup.pe_subnet_name
  virtual_network_name = data.azurerm_virtual_network.this.name
  resource_group_name  = data.azurerm_resource_group.network.name
}

module "mysql" {
  for_each = try(local.workspace.identity.mysql_servers, {})

  source = "./modules/mysql"

  name           = "${each.value.naming.org}-${each.value.naming.env}-${each.value.naming.region}-${each.value.naming.workload}"
  resource_group = each.value.resource_group
  tags           = try(each.value.tags, {})

  mysql          = each.value.mysql
  databases      = try(each.value.databases, [])
  configurations = try(each.value.configurations, {})

  administrator_password = module.mysql_password[each.key].value

  private = merge(
    try(each.value.private, { enabled = false }),
    try(each.value.private, {}).enabled == true ? {
      pe_subnet_id = data.azurerm_subnet.pe.id
      vnet_id      = data.azurerm_virtual_network.this.id
    } : {}
  )

  private_endpoint = {
    resource_group_name = data.azurerm_resource_group.network.name
    location            = data.azurerm_resource_group.network.location
  }
}
```

## MySQL SKU Tiers

| Tier | SKU Pattern | Use Case |
|------|-------------|----------|
| Burstable | `B_Standard_B1ms`, `B_Standard_B2s` | Dev/test, light workloads |
| General Purpose | `GP_Standard_D2ds_v4`, `GP_Standard_D4ds_v4` | Production, balanced workloads |
| Business Critical | `MO_Standard_E2ds_v4`, `MO_Standard_E4ds_v4` | High performance, mission-critical |

## High Availability

| Mode | Description | Availability |
|------|-------------|-------------|
| `SameZone` | Standby in same availability zone | Lower latency failover |
| `ZoneRedundant` | Standby in different availability zone | Higher resilience |

## Private Endpoints

### Supported Services

The module supports private endpoints for:
- **mysqlServer**: MySQL Flexible Server (`privatelink.mysql.database.azure.com`)

## Naming Convention

Resources are named using the prefix pattern: `{name}`

Example:
- MySQL Server: `mysql-{name}-001`
- Private Endpoint: `{name}-pe-mysql`

## Outputs

| Name | Description |
|------|-------------|
| `mysql` | Full MySQL Flexible Server resource |
| `id` | MySQL Server ID |
| `name` | MySQL Server name |
| `fqdn` | MySQL Server FQDN |
| `resource_group_name` | Resource Group where MySQL is deployed |
| `private` | Private endpoint and DNS zone details (if enabled) |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| azurerm | >= 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | >= 4.0.0 |

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `name` | Resource name prefix for all resources | string | yes |
| `resource_group` | Resource group configuration | object | yes |
| `mysql` | MySQL Flexible Server configuration | object | yes |
| `private` | Private endpoint configuration | object | yes |
| `administrator_password` | MySQL admin password (sensitive) | string | yes |
| `tags` | Extra tags merged with default tags | map(string) | no |
| `diagnostics` | Azure Monitor diagnostic settings | object | no |
| `databases` | List of databases to create | list(object) | no |
| `configurations` | Server configuration parameters (key/value) | map(string) | no |
| `private_endpoint` | Private endpoint resource group placement | object | no |

### Detailed Input Specifications

#### mysql

```hcl
object({
  name        = optional(string)
  name_suffix = optional(string, "001")

  sku_name = optional(string, "GP_Standard_D2ds_v4")
  version  = optional(string, "8.0.21")

  administrator_login   = string
  public_network_access = optional(string)  # Enabled | Disabled

  backup_retention_days        = optional(number, 7)
  geo_redundant_backup_enabled = optional(bool, false)

  zone = optional(string)

  high_availability = optional(object({
    mode                      = string  # SameZone | ZoneRedundant
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
```

#### databases

```hcl
list(object({
  name      = string
  charset   = optional(string, "utf8mb4")
  collation = optional(string, "utf8mb4_unicode_ci")
}))
```

## License

Apache 2.0 Licensed. See LICENSE for full details.

## Authors

Module managed by DNX Solutions.

## Contributing

Please read CONTRIBUTING.md for details on our code of conduct and the process for submitting pull requests.
