require 'spec_helper'

describe Spree::Order do

  let(:order) { create(:order) }
  let(:updater) { Spree::OrderUpdater.new(order) }

  context "#update_adjustments" do
    let(:originator) do
      originator = Spree::Promotion::Actions::CreateAdjustment.create
      calculator = Spree::Calculator::PerItem.create({:calculable => originator}, :without_protection => true)
      originator.calculator = calculator
      originator.save
      originator
    end

    def create_adjustment(label, amount)
      create(:adjustment, :adjustable => order,
                          :originator => originator,
                          :amount     => amount,
                          :locked     => true,
                          :label      => label)
    end

    it "should only include eligible adjustments in promo_total" do
      create_adjustment("Promotion A", -100)
      create(:adjustment, :adjustable => order,
                          :originator => nil,
                          :amount     => -1000,
                          :locked     => true,
                          :eligible   => false,
                          :label      => 'Bad promo')

      order.promo_total.to_f.should == -100.to_f
    end
  end

  context "coupon_code sql injection" do
    it "will sanitize the input" do
      order.coupon_code = "Let's do this"
      expect(order.find_promo_for_coupon_code).to be_nil
    end
  end
end

