lib = File.expand_path("../../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'libhoney'

writekey = "7aefa39399a474bd9f414a8e3f8d9691" # replace this with yours from https://ui.honeycomb.com/account
dataset = "factorial"


def factorial(n)
  return -1 * factorial(abs(n)) if n < 0
  return 1 if n == 0
  return n * factorial(n - 1)
end

# run factorial. libh_builder comes with some fields already populated
# (namely, "version", "num_threads", and "builder")
def run_fact(low, high, libh_builder)
  for i in low..high do
    ev = libh_builder.event
    ev.metadata = { :fn => "run_fact",
                    :i => i }
    ev.with_timer("fact") do
      res = factorial(10 + i)
      ev.add_field("retval", res)
    end
    ev.send
  end
end

def read_responses(resp_queue)
  loop do
    resp = resp_queue.pop()
    break if resp == nil
    puts "sending event with metadata #{resp.metadata} took #{resp.duration*1000}ms and got response code #{resp.status_code}"
  end
end
    

libhoney = Libhoney::Client.new(:writekey => writekey,
                                :dataset => dataset,
                                :max_concurrent_batches => 1)

resps = libhoney.responses()
Thread.new do
  begin
    # attach fields to top-level instance
    libhoney.add_field("version", "3.4.5")
    libhoney.add_dynamic_field("num_threads", Proc.new { Thread.list.select {|thread| thread.status == "run"}.count })

    # sends an event with "version", "num_threads", and "status" fields
    libhoney.send_now({:status => "starting run"})
    run_fact(1, 20, libhoney.builder({:range => "low"}))
    run_fact(31, 40, libhoney.builder({:range => "high"}))

    # sends an event with "version", "num_threads", and "status" fields
    libhoney.send_now({:status => "ending run"})
    libhoney.close(true)
  rescue Exception => e
    puts e
  end
end

read_responses(resps)
