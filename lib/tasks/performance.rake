namespace :performance do
  desc "Migrate and prewarm shared read catalogues before serving a new release"
  task prepare: ["db:migrate", :environment] do
    unless ModuleRecordReadVersion.read
      abort "Read-version triggers are unavailable. For a schema-only restore, run db:migrate:redo VERSION=20261116120000 before retrying performance:prepare."
    end
    load Rails.root.join("script/warm_form_catalogues.rb")
  end
end
