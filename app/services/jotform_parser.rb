require_relative '../../config/sequel'

module MemberTracker
  # Parses JotForm membership-survey responses stored in log notes.
  #
  # The JotForm survey captures member interest data (topics, frequencies,
  # modes, callback preference) as free-text pasted into log notes.  Notes
  # that contain a line matching /jotform/ are treated as survey responses.
  #
  # Public interface:
  #   JotformParser.call          -> array of [mbr_id, codes, log_id, other_str]
  #   JotformParser.parse_note(s) -> [codes, other] or nil
  #   JotformParser.categorize(s, sym) -> code string or nil
  class JotformParser
    LOOKBACK_DAYS = 365

    # Queries DB for dues payments in the last year and returns parsed survey
    # data for members whose log notes contain JotForm responses.
    # Returns an array of [mbr_id, codes_array, log_id, other_str].
    def self.call
      cutoff  = DateTime.now - LOOKBACK_DAYS
      log_ids = []
      DB[:payments].where(payment_type_id: 5).each do |pmt|
        log_ids << [pmt[:mbr_id], pmt[:log_id]] if pmt[:ts].to_datetime > cutoff
      end

      mbr_codes = []
      log_ids.each do |mbr_id, log_id|
        note = DB[:logs].first(id: log_id)&.fetch(:notes, nil)
        next unless note

        result = parse_note(note)
        next unless result

        codes, other = result
        other_str = other.filter_map { |k, v| "#{k}:#{v}" unless v.empty? }.join
        mbr_codes << [mbr_id, codes, log_id, other_str]
      end
      mbr_codes
    end

    # Parses a single log note for JotForm survey content.
    # Returns [codes_array, other_hash] or nil if no survey data is found.
    def self.parse_note(note)
      return nil unless /^.*jotform/.match(note)

      question_h  = { topic: [], freq: [], mode: [], callback: [] }
      active_q    = nil
      cont_from_q = false
      capture     = false

      note.split("\n").each do |line|
        if !capture && /^.*jotform/.match(line)
          capture = true
        elsif capture
          cont_from_q = true if /^What/.match(line)

          if /topics/.match(line)
            active_q = :topic
            question_h[active_q] << /.*\?(.*)/.match(line)[1].strip
          elsif /freq/.match(line)
            active_q = :freq
            question_h[active_q] << /.*\?(.*)/.match(line)[1].strip
          elsif /mode/.match(line)
            active_q = :mode
            question_h[active_q] << /.*\?(.*)/.match(line)[1].strip
          elsif /Would/.match(line)
            active_q = :callback
            question_h[active_q] << /.*\?(.*)/.match(line)[1].strip
          elsif cont_from_q
            break if /^\*\*/.match(line)
            question_h[active_q] << line.strip
          end
        end
      end

      return nil if active_q.nil? || question_h[active_q].empty?

      codes = []
      other = { topics: [], modes: [] }

      question_h[:topic].each do |t|
        r = categorize(t, :topic)
        if /^T11\|/.match(r)
          codes << "T11"
          other[:topics] << r.split('|')[1]
        else
          codes << r
        end
      end

      question_h[:freq].each { |f| codes << categorize(f, :freq) }

      question_h[:mode].each do |m|
        r = categorize(m, :mode)
        if /^F5\|/.match(r)
          codes << "F5"
          other[:modes] << r.split('|')[1]
        else
          codes << r
        end
      end

      question_h[:callback].each do |cb|
        codes << (/Yes/.match(cb) ? "CB1" : "CB2")
      end

      [codes, other]
    end

    # Maps a free-text survey answer to its category code.
    # Returns a String code (e.g. "T2", "F1", "M2") or nil for :freq with no match.
    # Note: unrecognized topics return "T11|<text>"; unrecognized modes return "F5|<text>".
    def self.categorize(answer_str, question_symbol)
      case question_symbol
      when :topic
        topics = {
          "T1"  => /^Portable Oper/, "T2"  => /^Contest/,
          "T3"  => /^Beginner op/,   "T4"  => /^Technical/,
          "T5"  => /^Product De/,    "T6"  => /^Radio Hi/,
          "T7"  => /^Distance Com/,  "T8"  => /^Digital Mode/,
          "T9"  => /^Propagation/,   "T10" => /^Emergency prep/
        }
        topics.find { |_, rx| rx.match(answer_str) }&.first || "T11|#{answer_str}"
      when :freq
        freqs = { "F1" => /^Hig/, "F2" => /^VHF/, "F3" => /^Mic/, "F4" => /^Low/, "F5" => /^Non/ }
        freqs.find { |_, rx| rx.match(answer_str) }&.first
      when :mode
        modes = { "M1" => /^Voice/, "M2" => /^CW/, "M3" => /^Digital/, "M4" => /^None/ }
        modes.find { |_, rx| rx.match(answer_str) }&.first || "F5|#{answer_str}"
      end
    end
  end
end
