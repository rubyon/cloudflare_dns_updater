require 'net/http'
require 'json'
require 'uri'
require 'time'

# 출력 버퍼링 해제 (Docker 로그 실시간 출력)
$stdout.sync = true

# 환경 변수에서 API 정보 가져오기
CF_API_TOKEN = ENV["CLOUDFLARE_API_TOKEN"]
ZONE_ID = ENV["CLOUDFLARE_ZONE_ID"]
CHECK_INTERVAL_S = ENV["CHECK_INTERVAL_S"].to_i

# 도메인 목록 가져오기 (공백 1개 이상 허용)
domains = ENV["CLOUDFLARE_DOMAINS"].to_s.split(/\s+/).map(&:strip).uniq

# 현재 시간 반환 함수 (Docker에서 TZ가 Asia/Seoul이므로 별도 설정 불필요)
def current_time
  Time.now.strftime("[%Y-%m-%d %H:%M:%S]")
end

def get_current_ip
  ip_services = [
    "https://api64.ipify.org",
    "https://checkip.amazonaws.com",
    "https://ipv4.icanhazip.com",
    "https://ifconfig.me"
  ]

  ip_services.each do |service|
    begin
      uri = URI(service)
      response = Net::HTTP.get(uri).strip.gsub(/[^0-9.]/, '')
      return response if response.match(/\b(?:\d{1,3}\.){3}\d{1,3}\b/)
    rescue StandardError => e
      puts "#{current_time} ⚠️ #{service} 실패: #{e.message}"
    end
  end

  puts "#{current_time} ❌ 모든 IP 조회 서비스 실패"
  nil
end

def fetch_dns_records
  uri = URI("https://api.cloudflare.com/client/v4/zones/#{ZONE_ID}/dns_records")
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{CF_API_TOKEN}"
  request["Content-Type"] = "application/json"

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
  json_response = JSON.parse(response.body)

  if json_response["success"]
    json_response["result"].select { |record| record["type"] == "A" }
  else
    puts "#{current_time} Cloudflare API 오류: #{json_response["errors"]}"
    []
  end
rescue StandardError => e
  puts "#{current_time} Cloudflare API 요청 실패: #{e.message}"
  []
end

def update_dns_record(domain, record_id, new_ip)
  uri = URI("https://api.cloudflare.com/client/v4/zones/#{ZONE_ID}/dns_records/#{record_id}")
  request = Net::HTTP::Put.new(uri)
  request["Authorization"] = "Bearer #{CF_API_TOKEN}"
  request["Content-Type"] = "application/json"
  request.body = {
    type: "A",
    name: domain,
    content: new_ip,
    ttl: 1,
    proxied: false
  }.to_json

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
  json_response = JSON.parse(response.body)

  if json_response["success"]
    puts "#{current_time} ✅ [#{domain}] Cloudflare DNS 업데이트 성공: #{new_ip}"
  else
    puts "#{current_time} ❌ [#{domain}] 업데이트 실패: #{json_response["errors"]}"
  end
rescue StandardError => e
  puts "#{current_time} Cloudflare API 요청 실패: #{e.message}"
end

puts "#{current_time} [INFO] Cloudflare DNS Updater 시작됨. 체크 간격: #{CHECK_INTERVAL_S}초"

loop do
  begin
    current_ip = get_current_ip
    if current_ip
      dns_records = fetch_dns_records
      domain_map = dns_records.each_with_object({}) { |record, hash| hash[record["name"]] = record["id"] }

      domains.each do |domain|
        record_id = domain_map[domain]
        if record_id
          existing_ip = dns_records.find { |r| r["id"] == record_id }["content"]

          if existing_ip && current_ip != existing_ip
            puts "#{current_time} 🔄 [#{domain}] IP 변경 감지! 기존: #{existing_ip} → 새 IP: #{current_ip}"
            update_dns_record(domain, record_id, current_ip)
          else
            puts "#{current_time} ✅ [#{domain}] IP 변경 없음 (현재 IP: #{current_ip})"
          end
        else
          puts "#{current_time} ❌ [#{domain}] 해당하는 Record ID를 찾을 수 없음"
        end
      end
    else
      puts "#{current_time} ❌ 전체 IP 조회 실패"
    end
  rescue StandardError => e
    puts "#{current_time} ❌ 예기치 않은 오류 발생: #{e.message}"
    puts e.backtrace.join("\n")
  ensure
    sleep CHECK_INTERVAL_S
  end
end
