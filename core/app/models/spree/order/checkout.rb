module Spree
  class Order < ActiveRecord::Base
    module Checkout
      def self.included(klass)
        klass.class_eval do
          class_attribute :next_event_transitions
          class_attribute :previous_states
          class_attribute :checkout_flow
          class_attribute :checkout_steps
          class_attribute :removed_transitions

          def self.checkout_flow(&block)
            if block_given?
              @checkout_flow = block
              define_state_machine!
            else
              @checkout_flow
            end
          end

          def self.define_state_machine!
            # Needs to be an ordered hash to preserve flow order
            self.checkout_steps = ActiveSupport::OrderedHash.new
            self.next_event_transitions = []
            self.previous_states = [:cart]
            self.removed_transitions = []

            # Build the checkout flow using the checkout_flow defined either
            # within the Order class, or a decorator for that class.
            #
            # This method may be called multiple times depending on if the
            # checkout_flow is re-defined in a decorator or not.
            instance_eval(&checkout_flow)

            klass = self

            # To avoid a ton of warnings when the state machine is re-defined
            StateMachine::Machine.ignore_method_conflicts = true
            # To avoid multiple occurrences of the same transition being defined
            # On first definition, state_machines will not be defined
            state_machines.clear if respond_to?(:state_machines)
            state_machine :state, :initial => :cart, :use_transactions => false, :action => :save_state do
              klass.next_event_transitions.each { |t| transition(t.merge(:on => :next)) }

              # Persist the state on the order
              after_transition do |order|
                order.state = order.state
                order.save
              end

              event :cancel do
                transition :to => :canceled, :if => :allow_cancel?
              end

              event :return do
                transition :to => :returned, :from => :awaiting_return, :unless => :awaiting_returns?
              end

              event :resume do
                transition :to => :resumed, :from => :canceled, :if => :allow_resume?
              end

              event :authorize_return do
                transition :to => :awaiting_return
              end

              before_transition :to => :complete do |order|
                begin
                  order.process_payments! if order.payment_required?
                rescue Spree::Core::GatewayError
                  !!Spree::Config[:allow_checkout_on_gateway_error]
                end
              end

              before_transition :to => :delivery, :do => :remove_invalid_shipments!

              after_transition :to => :complete, :do => :finalize!
              after_transition :to => :delivery, :do => :create_tax_charge!
              after_transition :to => :resumed,  :do => :after_resume
              after_transition :to => :canceled, :do => :after_cancel

              after_transition :from => :delivery,  :do => :create_shipment!
            end

            alias_method :save_state, :save
          end

          def self.go_to_state(name, options={})
            self.checkout_steps[name] = options
            previous_states.each do |state|
              add_transition({:from => state, :to => name}.merge(options))
            end
            if options[:if]
              self.previous_states << name
            else
              self.previous_states = [name]
            end
          end

          def self.insert_checkout_step(name, options = {})
            before = options.delete(:before)
            after = options.delete(:after) unless before
            after = self.checkout_steps.keys.last unless before || after

            cloned_steps = self.checkout_steps.clone
            cloned_removed_transitions = self.removed_transitions.clone
            self.checkout_flow do
              cloned_steps.each_pair do |key, value|
                self.go_to_state(name, options) if key == before
                self.go_to_state(key, value)
                self.go_to_state(name, options) if key == after
              end
              cloned_removed_transitions.each do |transition|
                self.remove_transition(transition)
              end
            end
          end

          def self.remove_checkout_step(name)
            cloned_steps = self.checkout_steps.clone
            cloned_removed_transitions = self.removed_transitions.clone
            self.checkout_flow do
              cloned_steps.each_pair do |key, value|
                self.go_to_state(key, value) unless key == name
              end
              cloned_removed_transitions.each do |transition|
                self.remove_transition(transition)
              end
            end
          end

          def self.remove_transition(options={})
            self.removed_transitions << options
            if transition = find_transition(options)
              self.next_event_transitions.delete(transition)
            end
          end

          def self.find_transition(options={})
            self.next_event_transitions.detect do |transition|
              transition[options[:from].to_sym] == options[:to].to_sym
            end
          end

          def self.next_event_transitions
            @next_event_transitions ||= []
          end

          def self.checkout_steps
            @checkout_steps ||= ActiveSupport::OrderedHash.new
          end

          def self.add_transition(options)
            self.next_event_transitions << { options.delete(:from) => options.delete(:to) }.merge(options)
          end

          def checkout_steps
            checkout_steps = []
            # TODO: replace this with each_with_object once Ruby 1.9 is standard
            self.class.checkout_steps.each do |step, options|
              if options[:if]
                next unless options[:if].call(self)
              end
              checkout_steps << step
            end
            steps = checkout_steps.map(&:to_s)
            # Ensure there is always a complete step
            steps << "complete" unless steps.include?("complete")
            steps
          end

          def has_checkout_step?(step)
            step.present? ? self.checkout_steps.include?(step) : false
          end

          def checkout_step_index(step)
            self.checkout_steps.index(step)
          end

          def self.removed_transitions
            @removed_transitions ||= []
          end

          def can_go_to_state?(state)
            return false unless self.state.present? && has_checkout_step?(state) && has_checkout_step?(self.state)
            checkout_step_index(state) > checkout_step_index(self.state)
          end

          define_callbacks :updating_from_params

          set_callback :updating_from_params, :before, :update_params_payment_source

          def update_from_params(order_params)
            success = false
            @updating_params = order_params
            run_callbacks :updating_from_params do
              success = self.update_attributes(@updating_params[:order])
            end
            @updating_params = nil
            success
          end

          private
          # For payment step, filter order parameters to produce the expected nested attributes for a
          # single payment and its source, discarding attributes for payment methods other than the one selected
          def update_params_payment_source
            if self.payment?
              if @updating_params[:payment_source].present? && source_params = @updating_params.delete(:payment_source)[@updating_params[:order][:payments_attributes].first[:payment_method_id].underscore]
                @updating_params[:order][:payments_attributes].first[:source_attributes] = source_params
              end
              if (@updating_params[:order][:payments_attributes])
                @updating_params[:order][:payments_attributes].first[:amount] = self.total
              end
            end
          end
        end
      end
    end
  end
end
