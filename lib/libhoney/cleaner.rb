module Libhoney
  module Cleaner
    ENCODING_OPTIONS = { invalid: :replace, undef: :replace }.freeze
    RECURSION = '[RECURSION]'.freeze
    RAISED = '[RAISED]'.freeze

    def clean_data(data, seen = {})
      return nil if data.nil?

      protection =  case data
                    when Hash, Array, Set
                      return seen[data] if seen[data]

                      seen[data] = RECURSION
                    end

      value = case data
              when Hash
                clean_hash = {}
                data.each do |key, val|
                  clean_hash[key] = clean_data(val, seen)
                end
                clean_hash
              when Array, Set
                data.map do |element|
                  clean_data(element, seen)
                end
              when Numeric, TrueClass, FalseClass
                data
              when String
                clean_string(data)
              else
                str = begin
                        data.to_s
                      rescue StandardError
                        RAISED
                      end
                clean_string(str)
              end

      seen[data] = value if protection
      value
    end

    def clean_string(str)
      return str if str.encoding == Encoding::UTF_8 && str.valid_encoding?

      str.encode(Encoding::UTF_8, ENCODING_OPTIONS)
    end
  end
end
