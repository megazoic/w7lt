require_relative '../config/sequel'

module MemberTracker
  class PaymentType < Sequel::Model
    one_to_many :payments, :class=>"MemberTracker::Payment", key: :payment_type_id
    @types = PaymentType.all
    class << self
      attr_reader :types
    end
    def PaymentType.getID(name)
      pts = DB.from(:payment_types).select(:id, :type).all
      p_id = ''
      pts.each do |pt|
        if pt[:type] == name
          p_id = pt[:id]
        end
      end
      p_id
    end
  end
end