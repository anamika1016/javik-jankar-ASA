# Pin npm packages by running ./bin/importmap

pin "application", preload: false
pin "layout", preload: false
pin "dashboard_reports", preload: false
pin "login", preload: false
pin "password_toggles"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
