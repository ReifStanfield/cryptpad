variable "image" {
  type        = string
  description = "CryptPad image built from the form-image-answers branch"
  default     = "cryptpad-forms:e647263"
}

variable "main_domain" {
  type        = string
  description = "Public origin users load (Tailscale Funnel on 443)"
  default     = "https://takeo.korat-wyvern.ts.net"
}

variable "sandbox_domain" {
  type        = string
  description = "Separate sandbox origin (Tailscale Funnel on 8443)"
  default     = "https://takeo.korat-wyvern.ts.net:8443"
}

variable "max_upload_mb" {
  type        = number
  description = "Max file size in MB; guests get the same limit (the highest the server allows them)"
  default     = 20
}

job "cryptpad" {
  type = "service"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "takeo"
  }

  group "cryptpad" {
    count = 1

    network {
      port "http" { static = 3000 }
      port "ws" { static = 3003 }
    }

    task "cryptpad" {
      driver = "docker"

      config {
        image = var.image
        ports = ["http", "ws"]

        ulimit {
          nofile = "1000000:1000000"
        }

        # Named Docker volumes so data survives restarts and redeploys
        mount {
          type     = "bind"
          source   = "local/config.js"
          target   = "/cryptpad/config/config.js"
          readonly = true
        }
        mount {
          type   = "volume"
          source = "cryptpad-blob"
          target = "/cryptpad/blob"
        }
        mount {
          type   = "volume"
          source = "cryptpad-block"
          target = "/cryptpad/block"
        }
        mount {
          type   = "volume"
          source = "cryptpad-data"
          target = "/cryptpad/data"
        }
        mount {
          type   = "volume"
          source = "cryptpad-datastore"
          target = "/cryptpad/datastore"
        }
        mount {
          type   = "volume"
          source = "cryptpad-customize"
          target = "/cryptpad/customize"
        }
        # Client-side overrides, served in place of customize.dist/application_config.js
        mount {
          type     = "bind"
          source   = "local/application_config.js"
          target   = "/cryptpad/customize/application_config.js"
          readonly = true
        }
      }

      template {
        destination = "local/config.js"
        change_mode = "restart"
        data        = <<EOT
module.exports = {
    httpUnsafeOrigin: '${var.main_domain}',
    httpSafeOrigin: '${var.sandbox_domain}',
    httpAddress: '0.0.0.0',
    httpPort: 3000,
    websocketPort: 3003,
    maxUploadSize: ${var.max_upload_mb} * 1024 * 1024,
    // Guests get the same limit as registered users
    maxGuestUploadSize: ${var.max_upload_mb} * 1024 * 1024,
    // Add your public signing key here (Settings > Account) to access the admin panel
    adminKeys: [],
    installMethod: 'docker',
};
EOT
      }

      template {
        destination = "local/application_config.js"
        change_mode = "restart"
        data        = <<EOT
(() => {
const factory = (AppConfig) => {
    // Guests can't create documents (forms included) but can still
    // open and answer the forms shared with them. Image answers are
    // uploaded without creating a document, so they keep working.
    AppConfig.disableAnonymousPadCreation = true;
    // Guests can't keep documents in a guest CryptDrive
    AppConfig.disableAnonymousStore = true;
    return AppConfig;
};

if (typeof(module) !== 'undefined' && module.exports) {
    module.exports = factory(
        require('../www/common/application_config_internal.js')
    );
} else if ((typeof(define) !== 'undefined' && define !== null) && (define.amd !== null)) {
    define(['/common/application_config_internal.js'], factory);
}
})();
EOT
      }

      env {
        CPAD_MAIN_DOMAIN    = var.main_domain
        CPAD_SANDBOX_DOMAIN = var.sandbox_domain
        CPAD_CONF           = "/cryptpad/config/config.js"
      }

      resources {
        cpu    = 1000
        memory = 1024
      }

      service {
        name     = "cryptpad"
        port     = "http"
        provider = "nomad"

        check {
          type     = "http"
          path     = "/"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
