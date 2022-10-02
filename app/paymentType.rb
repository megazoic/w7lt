require_relative '../config/sequel'

module MemberTracker
  class PaymentType < Sequel::Model
    one_to_many :payments, :class=>"MemberTracker::Payment", key: :payment_type_id
    @types = PaymentType.all
    class << self
      attr_reader :types
    end
  end
end