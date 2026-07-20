Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      post "login", to: "sessions#create"
      post "login/otp/send", to: "otp_logins#send_otp"
      post "login/otp/verify", to: "otp_logins#verify_otp"
      post "forgot-password/send-otp", to: "password_resets#send_otp"
      post "forgot-password/reset", to: "password_resets#reset"
      get "me", to: "sessions#show"
      delete "logout", to: "sessions#destroy"

      # Jeevika Jankar (VRP) — React Native APIs; web /vrps routes unchanged
      get "jeevika-jankars/form-options", to: "jeevika_jankars#form_options"
      get "jeevika-jankars/approvals", to: "jeevika_jankar_approvals#index"
      patch "jeevika-jankars/:id/approve", to: "jeevika_jankar_approvals#approve"
      patch "jeevika-jankars/:id/reject", to: "jeevika_jankar_approvals#reject"
      resources :jeevika_jankars, path: "jeevika-jankars", only: [ :index, :create, :show ] do
        member do
          patch :send_for_approval
        end
      end

      # Jeevika Jankar master lookups for React clients. These routes are kept
      # separate from the existing /modules/* web screens.
      get "jeevika-jankar-types", to: "jeevika_jankar_masters#types"
      post "jeevika-jankar-types", to: "jeevika_jankar_masters#create_type"
      get "jeevika-jankar-masters/all-list", to: "jeevika_jankar_masters#all_list"
      get "jeevika-jankar-masters/states", to: "jeevika_jankar_masters#states"
      get "jeevika-jankar-masters/districts", to: "jeevika_jankar_masters#districts"
      get "jeevika-jankar-masters/blocks", to: "jeevika_jankar_masters#blocks"
      get "jeevika-jankar-masters/gram-panchayats", to: "jeevika_jankar_masters#gram_panchayats"
      get "jeevika-jankar-masters/villages", to: "jeevika_jankar_masters#villages"
      get "jeevika-jankar-masters/months", to: "jeevika_jankar_masters#months"
      get "jeevika-jankar-masters/parent-offices", to: "jeevika_jankar_masters#parent_offices"
      get "jeevika-jankar-masters/office-categories", to: "jeevika_jankar_masters#office_categories"
      get "jeevika-jankar-masters/sub-offices", to: "jeevika_jankar_masters#sub_offices"

      # Farmer Target modules — React Native APIs; web /modules/* unchanged
      get "farmer-trainings/form-options", to: "farmer_trainings#form_options"
      resources :farmer_trainings, path: "farmer-trainings", only: [ :index, :create, :show ]

      get "seed-distribution-targets/form-options", to: "seed_distribution_targets#form_options"
      resources :seed_distribution_targets, path: "seed-distribution-targets", only: [ :index, :create, :show ]

      get "papl360-targets/form-options", to: "papl360_targets#form_options"
      resources :papl360_targets, path: "papl360-targets", only: [ :index, :create, :show ]

      get "add-farmer-forms/form-options", to: "add_farmer_forms#form_options"
      resources :add_farmer_forms, path: "add-farmer-forms", only: [ :index, :create, :show ]
    end
  end


  get    "login",  to: "sessions#new",     as: :login
  post   "login",  to: "sessions#create"
  get    "forgot-password", to: "sessions#forgot_password", as: :forgot_password
  post   "forgot-password/send-otp", to: "sessions#send_forgot_password_otp", as: :send_forgot_password_otp
  post   "forgot-password/reset", to: "sessions#reset_forgot_password", as: :reset_forgot_password
  get    "vrp-agreement", to: "sessions#agreement", as: :vrp_agreement
  post   "vrp-agreement", to: "sessions#complete_agreement"
  get    "vrp-agreements", to: "vrp_agreements#index", as: :vrp_agreements
  get    "vrp-agreements/export", to: "vrp_agreements#export", as: :export_vrp_agreements
  delete "vrp-agreements/:id", to: "vrp_agreements#destroy", as: :reset_vrp_agreement
  get    "vrp-agreements/:id", to: "vrp_agreements#show", as: :vrp_agreement_record
  get    "logout", to: "sessions#destroy", as: nil
  delete "logout", to: "sessions#destroy", as: :logout

  root "sessions#new"
  get "dashboard", to: "modules#dashboard", as: :dashboard
  get "dashboard/vrp-list/:list_type", to: "modules#vrp_dashboard_list", as: :vrp_dashboard_list
  delete "dashboard/vrp-mapped-villages/:id", to: "modules#destroy_vrp_mapped_village", as: :destroy_vrp_mapped_village
  get "dashboard/farmer-training-participation", to: "modules#farmer_training_participation", as: :farmer_training_participation
  get "dashboard/farmer-training-target-status", to: "modules#farmer_training_target_status", as: :farmer_training_target_status
  get "dashboard/weekly-activity-target-report", to: "modules#weekly_activity_target_report", as: :weekly_activity_target_report

  resources :users, except: [:show] do
    patch :toggle_status, on: :member
    patch :set_status, on: :member
  end

  resources :afls, only: [:index, :destroy] do
    post :import, on: :collection
    delete :bulk_destroy, on: :collection
    get "import_reports/:id", action: :import_report, as: :import_report, on: :collection
  end

  resources :vrp_ics_mappings, only: [:index, :create, :destroy] do
    collection do
      get :ics_options
      get :village_options
      get :farmers
    end
  end

  resources :target_mappings, only: [:index, :create, :destroy] do
    get :vrp_mappings, on: :collection
  end

  get "farmer-farm-information", to: "farmer_farm_information#index", as: :farmer_farm_information
  post "farmer-farm-information", to: "farmer_farm_information#create"
  post "farmer-farm-information/import", to: "farmer_farm_information#import", as: :import_farmer_farm_information
  get "farmer-farm-information/export", to: "farmer_farm_information#export", as: :export_farmer_farm_information
  get "farmer-farm-information/list", to: "farmer_farm_information#list", as: :list_farmer_farm_information
  get "farmer-farm-information/ics-exit-declaration", to: "farmer_farm_information#ics_exit_declaration", as: :ics_exit_declaration_farmer_farm_information
  post "farmer-farm-information/ics-exit-declaration", to: "farmer_farm_information#create_ics_exit_declaration"
  get "farmer-farm-information/ics-exit-declaration/:id/edit", to: "farmer_farm_information#edit_ics_exit_declaration", as: :edit_ics_exit_declaration_record
  get "farmer-farm-information/ics-exit-declaration/:id", to: "farmer_farm_information#show_ics_exit_declaration", as: :ics_exit_declaration_record
  patch "farmer-farm-information/ics-exit-declaration/:id", to: "farmer_farm_information#update_ics_exit_declaration"
  delete "farmer-farm-information/ics-exit-declaration/:id", to: "farmer_farm_information#destroy_ics_exit_declaration"
  get "farmer-farm-information/farm-map", to: "farmer_farm_map_uploads#farm_map", as: :farm_map_farmer_farm_information
  get "farmer-farm-information/crop-map-session-wise", to: "farmer_farm_map_uploads#crop_map_session_wise", as: :crop_map_session_wise_farmer_farm_information
  post "farmer-farm-information/map-uploads", to: "farmer_farm_map_uploads#create", as: :farmer_farm_map_uploads
  get "farmer-farm-information/map-uploads/:id/edit", to: "farmer_farm_map_uploads#edit", as: :edit_farmer_farm_map_upload
  patch "farmer-farm-information/map-uploads/:id/set_status", to: "farmer_farm_map_uploads#set_status"
  patch "farmer-farm-information/map-uploads/:id", to: "farmer_farm_map_uploads#update", as: :farmer_farm_map_upload
  delete "farmer-farm-information/map-uploads/:id", to: "farmer_farm_map_uploads#destroy"
  resources :farm_crop_area_details, path: "farmer-farm-information/farm-crop-area-details", only: [:index, :create, :edit, :update, :destroy] do
    post :import, on: :collection
    get :export, on: :collection
    patch :set_status, on: :member
  end
  resources :seed_planting_materials, path: "farmer-farm-information/seed-planting-materials", only: [:index, :create, :edit, :update, :destroy] do
    post :import, on: :collection
    get :export, on: :collection
    patch :set_status, on: :member
  end
  resources :soil_conditioner_fertility_input_records, path: "farmer-farm-information/soil-conditioner-fertility-input-records", only: [:index, :create, :edit, :update, :destroy] do
    post :import, on: :collection
    get :export, on: :collection
    patch :set_status, on: :member
  end
  resources :on_farm_input_records, path: "farmer-farm-information/on-farm-input-records", only: [:index, :create, :edit, :update, :destroy] do
    post :import, on: :collection
    get :export, on: :collection
    patch :set_status, on: :member
  end
  resources :disease_pest_weed_management_records, path: "farmer-farm-information/disease-pest-weed-management-records", only: [:index, :create, :edit, :update, :destroy] do
    post :import, on: :collection
    get :export, on: :collection
    patch :set_status, on: :member
  end
  resources :contamination_control_records, path: "farmer-farm-information/contamination-control-records", only: [:index, :create, :edit, :update, :destroy] do
    post :import, on: :collection
    get :export, on: :collection
    patch :set_status, on: :member
  end
  resources :production_harvest_details, path: "farmer-farm-information/production-harvest-details", only: [:index, :create, :edit, :update, :destroy] do
    post :import, on: :collection
    get :export, on: :collection
    patch :set_status, on: :member
  end
  resources :post_harvest_handling_storage_records, path: "farmer-farm-information/post-harvest-handling-storage-records", only: [:index, :create, :edit, :update, :destroy] do
    post :import, on: :collection
    get :export, on: :collection
    patch :set_status, on: :member
  end
  resources :sale_records, path: "farmer-farm-information/sale-records", only: [:index, :create, :edit, :update, :destroy] do
    post :import, on: :collection
    get :export, on: :collection
    patch :set_status, on: :member
  end
  resources :dispatch_records, path: "farmer-farm-information/dispatch-records", only: [:index, :create, :edit, :update, :destroy] do
    post :import, on: :collection
    get :export, on: :collection
    patch :set_status, on: :member
  end
  get "farmer-farm-information/:id/edit", to: "farmer_farm_information#edit", as: :edit_farmer_farm_information_record
  patch "farmer-farm-information/:id/set_status", to: "farmer_farm_information#set_status"
  patch "farmer-farm-information/:id", to: "farmer_farm_information#update", as: :farmer_farm_information_record
  delete "farmer-farm-information/:id", to: "farmer_farm_information#destroy"

  resources :modules, param: :slug, only: [:show], controller: :modules do
    post :records, action: :create, on: :member
    post :payment_details, action: :create_payment_detail, on: :member
    post :import, action: :import, on: :member
    get :export, action: :export, on: :member
    patch :bulk_update, action: :bulk_update, on: :member

    resources :records, controller: :modules, only: [:edit, :update, :destroy] do
      get :selected_farmers, on: :member
      get :export_selected_farmers, on: :member
      delete :selected_farmer, on: :member
      patch :toggle, action: :toggle_status, on: :member
      patch :set_status, action: :set_status, on: :member
      patch :send_for_approval, action: :send_bill_for_approval, on: :member
      patch :set_bill_state, action: :set_bill_state, on: :member
      patch :approve_bill, action: :approve_bill, on: :member
      patch :reject_bill, action: :reject_bill, on: :member
      patch :return_bill, action: :return_bill, on: :member
      get :download_bill, action: :download_bill, on: :member
    end
  end

  resources :vrps, only: [:index, :new, :create, :edit, :update, :show, :destroy] do
    collection do
      get :approvals
    end

    member do
      patch :set_active
      patch :send_for_approval
      patch :approve
      patch :reject
    end
  end
end
