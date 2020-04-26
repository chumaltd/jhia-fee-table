require "pathname"
require_relative "kempo_table"

Dir.each_child(ARGV[0]) do |file|
  next unless /csv$/.match(file)

  csv_path = Pathname(ARGV[0]) + file
  table = KempoTable.new(csv_path.to_s, ARGV[1])

  yaml_path = Pathname(ARGV[0]) + "#{File.basename(file, ".csv")}-#{table.premium_table["effective_date"]}.yaml"
  File.write(yaml_path.to_s, table.to_yaml)

  json_path = Pathname(ARGV[0]) + "#{File.basename(file, ".csv")}-#{table.premium_table["effective_date"]}.json"
  File.write(json_path.to_s, table.to_json)
end
