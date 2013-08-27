Sequel.migration do
  change do
    create_table(:email_jobs) do
      primary_key :id
      String :to, :null => false
      String :subject, :null => false
      String :body, :null => false
      String :sent
    end
  end
end
