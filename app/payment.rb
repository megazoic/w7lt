require_relative '../config/sequel'
module MemberTracker
  class Payment < Sequel::Model
    many_to_one :log, :class=>Log, key: :log_id
    many_to_one :auth_user, :class=>AuthUser, key: :a_user_id
    many_to_one :member, :class=>Member, key: :mbr_id
    one_to_many :auditLog, :class=>"MemberTracker::AuditLog", key: :pay_id
    many_to_one :paymentType, :class=>"MemberTracker::PaymentType", key: :payment_type_id
    many_to_one :paymentMethod, :class=>"MemberTracker::PaymentMethod", key: :payment_method_id
    @fees = {"none" => 0, "full" => 25, "family" => 30, "student" => 10, "honorary" => 0, "lifetime" => 0}
    class << self
      attr_reader :fees
    end
    def Payment.findLatestDues(mbr_id, name)
      latest_dp = nil
      type_id = PaymentType.getID(name)
      Member[mbr_id].payments.each do |p|
        if p.payment_type_id == type_id
          latest_dp = p.ts if latest_dp.nil? || p.ts > latest_dp
        end
      end
      latest_dp
    end
  end
end
