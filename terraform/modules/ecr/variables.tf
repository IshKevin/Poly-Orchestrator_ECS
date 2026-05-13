variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "repositories" {
  description = "Map of short names to repository configuration"
  type = map(object({
    scan_on_push     = optional(bool, true)
    keep_image_count = optional(number, 10)
  }))
  default = {}
}

variable "tags" {
  description = "Tags to merge onto every resource in this module"
  type        = map(string)
  default     = {}
}
