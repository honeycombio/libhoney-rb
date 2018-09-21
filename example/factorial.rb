lib = File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'libhoney'

# replace this with yours from https://ui.honeycomb.com/account
writekey = '7aefa39399a474bd9f414a8e3f8d9691'
dataset  = 'factorial'

def factorial(number)
  return -1 * factorial(abs(number)) if number < 0
  return 1 if number.zero?

  number * factorial(number - 1)
end

# run factorial. libh_builder comes with some fields already populated
# (namely, "version", "num_threads", and "range")
def run_factorial(low, high, libh_builder)
  (low..high).each do |i|
    event = libh_builder.event
    event.metadata = { fn: 'run_factorial', i: i }

    event.with_timer('factorial') do
      result = factorial(10 + i)
      event.add_field('retval', result)
    end

    event.send
  end
end

def read_responses(response_queue)
  loop do
    response = response_queue.pop
    puts response_queue.inspect
    break if response.nil?

    puts "Sent: Event with metadata #{response.metadata} in #{response.duration * 1000}ms."
    puts "Got:  Response code #{response.status_code}"
    puts
  end
end

libhoney = Libhoney::Client.new(writekey: writekey,
                                dataset:  dataset,
                                max_concurrent_batches: 1)

responses = libhoney.responses

Thread.new do
  begin
    # attach fields to top-level instance
    libhoney.add_field('version', '3.4.5')

    a_proc = proc { Thread.list.select { |thread| thread.status == 'run' }.count }
    libhoney.add_dynamic_field('num_threads', a_proc)

    # sends an event with "version", "num_threads", and "status" fields
    libhoney.send_now(status: 'starting run')
    run_factorial(1, 20, libhoney.builder(range: 'low'))
    run_factorial(31, 40, libhoney.builder(range: 'high'))

    # sends an event with "version", "num_threads", and "status" fields
    libhoney.send_now(status: 'ending run')
    libhoney.close
  rescue StandardError => e
    puts e
  end
end

read_responses(responses)
