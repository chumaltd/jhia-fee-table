require "bigdecimal"
require "csv"
require "json"
require "yaml"

class KempoTable
  RANGE_CHAR = /^～/
  RANK_COUNT = 50

  # column definitions
  CL_RANK = 0
  CL_LABEL = 1
  CL_RANK_MIN = 2
  CL_RANK_MAX = 4
  CL_INSURANCE_YOUNGER_TOTAL = 5
  CL_INSURANCE_YOUNGER_SALARY = 6
  CL_INSURANCE_ELDER_TOTAL = 7
  CL_INSURANCE_ELDER_SALARY = 8
  CL_PENSION_TOTAL = 9
  CL_PENSION_SALARY = 10

  attr_reader :premium_table

  def initialize(file_path, effective_date=nil)
    @file_path = file_path

    @start_row
    @end_row
    @premium_table = {}
    @premium_table["area"] = File.basename(file_path, ".*")
    @premium_table["effective_date"] = parse_date(effective_date)
    @premium_table["fee"] = []

    test_structure
    set_row_range

    parse_table
  end

  def to_json
    JSON.generate(@premium_table)
  end

  def to_yaml
    YAML.dump(@premium_table)
  end

  private

  def simple_avg(array)
    return nil if array.length == 0
    array.sum.to_f / array.length
  end

  def byte_average(str)
    str.nil? ? nil : simple_avg(str.split(//).map{|s| s.bytesize})
  end

  def purify_num(str)
    /^[1-9]/.match(str) ? fix_float(str) : nil
  end

  def fix_float(num_str)
    if /[.]/.match(num_str)
      num = BigDecimal(num_str)
      num.round(1).to_s("F")
    else
      num_str
    end
  end

  def parse_date(date_str)
    md = /^([0-9]{4})\S([0-9]{,2})/.match(date_str)
    return nil if md.nil?
    format("%04d-%02d-01", md[1], md[2])
  end

  # check index structure
  def test_structure
    test_rank_range_index
    test_rank_index
    test_salary_rate(CL_INSURANCE_YOUNGER_TOTAL, CL_INSURANCE_YOUNGER_SALARY)
    test_salary_rate(CL_INSURANCE_ELDER_TOTAL, CL_INSURANCE_ELDER_SALARY)
    test_salary_rate(CL_PENSION_TOTAL, CL_PENSION_SALARY)
  end

  def parse_table
    CSV.foreach(@file_path, encoding: "UTF-8").with_index(0) do |row, i|
      next if i < @start_row
      break if i > @end_row
      obj = {}
      ins_rank, pension_rank = parse_rank(row[CL_RANK])
      obj["rank"] = ins_rank.to_i
      obj["pension_rank"] = pension_rank.nil? ? nil : pension_rank.to_i
      obj["label"] = row[CL_LABEL]
      obj["rank_min"] = row[CL_RANK_MIN].to_i
      obj["rank_max"] = row[CL_RANK_MAX].to_i
      obj["insurance_younger_total"] = fix_float(row[CL_INSURANCE_YOUNGER_TOTAL])
      obj["insurance_younger_salary"] = fix_float(row[CL_INSURANCE_YOUNGER_SALARY])
      obj["insurance_elder_total"] = fix_float(row[CL_INSURANCE_ELDER_TOTAL])
      obj["insurance_elder_salary"] = fix_float(row[CL_INSURANCE_ELDER_SALARY])
      obj["pension_total"] = purify_num(row[CL_PENSION_TOTAL])
      obj["pension_salary"] = purify_num(row[CL_PENSION_SALARY])

      @premium_table["fee"] << obj
    end
    fill_pension_table
  end

  def fill_pension_table
    pension_rank = @premium_table["fee"].map{|rank| rank["pension_rank"] }.compact
    total = @premium_table["fee"].map{|rank| rank["pension_total"] }.compact
    salary = @premium_table["fee"].map{|rank| rank["pension_salary"] }.compact

    @premium_table["fee"].each_with_index do |rank, i|
      if rank["pension_rank"].nil?
        rank["pension_rank"] = i*2 < @premium_table["fee"].length ? pension_rank.first : pension_rank.last
      end
      if rank["pension_total"].nil?
        rank["pension_total"] = i*2 < @premium_table["fee"].length ? total.first : total.last
      end
      if rank["pension_salary"].nil?
        rank["pension_salary"] = i*2 < @premium_table["fee"].length ? salary.first : salary.last
      end
    end
  end

  def parse_rank(str)
    m = /([0-9]+)[^0-9]*([0-9]+)*/.match(str)
    [m[1], m[2]]
  end

  def set_row_range
    CSV.foreach(@file_path, encoding: "UTF-8").with_index(0) do |row, i|
      if /^1$/.match(row[CL_RANK].to_s)
        @start_row = i 
      end
      if /^#{RANK_COUNT}$/.match(row[CL_RANK].to_s)
        @end_row = i
        break
      end
    end
  end

  def test_salary_rate(total, salary)
    diff = []
    CSV.foreach(@file_path, encoding: "UTF-8") do |row|
      if /^[1-9]/.match(row[total])
        diff << (row[total].to_f - row[salary].to_f * 2).abs / row[total].to_f
      end
    end
    raise SalaryRateError if (diff.sum / diff.length) > 0.03
    puts "salary rate is validated"
  end

  def test_rank_index
    rank_value = []
    CSV.foreach(@file_path, encoding: "UTF-8") do |row|
      rank_value << row[CL_RANK]
    end
    raise RankIndexError if rank_value.map{|item| /^[1-9]/.match(item) ? 1 : 0 }.sum < RANK_COUNT
    raise RankIndexError if rank_value.map{|item| (item && item.length <= 6) ? 1 : 0 }.sum < RANK_COUNT
    puts "rank index is validated"
  end

  def test_rank_range_index
    range_scan = []
    CSV.foreach(@file_path, encoding: "UTF-8") do |row|
      row.each.with_index(0) do |cell, i|
        if RANGE_CHAR.match(cell.to_s.gsub(/[\(\)]/,''))
          range_scan[i] = range_scan[i].nil? ? 1 : range_scan[i] + 1
        end
      end
    end

    sep_idx = range_scan.index(range_scan.map{|i| i.nil? ? 0 : i}.max)
    puts "range separator found @ column index #{sep_idx}(count: #{range_scan[sep_idx]})"
    raise RankMinError if CL_RANK_MIN != sep_idx - 1
    raise RankMaxError if CL_RANK_MAX != sep_idx + 1
    puts "rank range index is validated with separator"
  end

end
