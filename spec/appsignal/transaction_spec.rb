require 'spec_helper'

describe Appsignal::Transaction do
  describe '.create' do
    before { Appsignal::Transaction.create('1', {}) }

    it 'should add the id to the thread' do
      Thread.current[:appsignal_transaction_id].should == '1'
    end

    it 'should add the transaction to the list' do
      Appsignal.transactions['1'].should be_a Appsignal::Transaction
    end
  end

  describe '.current' do
    let(:transaction) { Appsignal::Transaction.create('1', {}) }
    before { transaction }
    subject { Appsignal::Transaction.current }

    it 'should return the correct transaction' do
      should eq transaction
    end
  end

  describe 'transaction instance' do
    let(:transaction) do
      Appsignal::Transaction.create('1', {
        'HTTP_USER_AGENT' => 'IE6',
        'SERVER_NAME' => 'localhost',
        'action_dispatch.routes' => 'not_available'
      })
    end

    describe '#request' do
      subject { transaction.request }

      it { should be_a ActionDispatch::Request }
    end

    describe '#set_process_action_event' do
      let(:process_action_event) { notification_event }

      it 'should add a process action event' do
        transaction.set_process_action_event(process_action_event)

        transaction.process_action_event.should == process_action_event
        transaction.action.should == 'BlogPostsController#show'
      end
    end

    describe '#add_event' do
      let(:event) { mock(:event, :name => 'test') }

      it 'should add an event' do
        expect {
          transaction.add_event(event)
        }.to change(transaction, :events).to([event])
      end
    end

    describe '#add_exception' do
      let(:exception) { mock(:exception, :name => 'test') }

      it 'should add an exception' do
        expect {
          transaction.add_exception(exception)
        }.to change(transaction, :exception).to(exception)
      end
    end

    describe '#slow_request?' do
      let(:start) { Time.now }
      subject { transaction.slow_request? }

      context "duration" do
        before do
          transaction.set_process_action_event(
            notification_event(:start => start, :ending => start + duration)
          )
        end

        context "when it reasonably fast" do
          let(:duration) { 0.199 } # in seconds

          it { should be_false }
        end

        context "when the request took too long" do
          let(:duration) { 0.200 } # in seconds

          it { should be_true }
        end
      end

      context "when process action event is empty" do
        before { transaction.set_process_action_event(nil) }

        it { should be_false }
      end

      context "when process action event does not have a payload" do
        let(:event) { notification_event }
        before do
          event.instance_variable_set(:@payload, nil)
          transaction.set_process_action_event(event)
        end

        it { should be_false }
      end
    end

    describe "#slower?" do
      context "comparing to a slower transaction" do
        subject { regular_transaction.slower?(slow_transaction) }

        it { should be_false }
      end

      context "comparing to a faster transaction" do
        subject { slow_transaction.slower?(regular_transaction) }

        it { should be_true }
      end
    end

    describe "#truncate!" do
      subject { slow_transaction }

      it "should clear the process action payload and events" do
        subject.truncate!

        subject.process_action_event.payload.should be_empty
        subject.events.should be_empty
      end
    end

    describe "#convert_values_to_primitives!" do
      let(:transaction) { slow_transaction }
      let(:action_event_payload) { transaction.process_action_event.payload }
      let(:event_payload) { transaction.events.first.payload }
      subject { transaction.convert_values_to_primitives! }

      context "with values that need to be converted" do
        before do
          action_event_payload.merge!(:model => Class.new)
          event_payload.merge!(:weird => Class.new)
        end

        it "changes the action event payload" do
          expect { subject }.
            to change(transaction.process_action_event, :payload)
        end

        it "changes all event payloads" do
          expect { subject }.to change(transaction.events.first, :payload)
        end
      end

      context "without values that need to be converted" do

        it "doesn't change the action event payload" do
          before = action_event_payload.dup
          subject
          action_event_payload.should == before
        end

        it " doesn't change the event payloads" do
          before = event_payload.dup
          subject
          event_payload.should == before
        end
      end
    end

    describe "#type" do
      context "with a regular transaction" do
        subject { regular_transaction.type }

        it { should == :regular_request }
      end

      context "with a slow transaction" do
        subject { slow_transaction.type }

        it { should == :slow_request }
      end

      context "with an exception transaction" do
        subject { transaction_with_exception.type }

        it { should == :exception }
      end
    end

    describe '#to_hash' do
      let(:formatter) { Appsignal::TransactionFormatter }
      subject { transaction.to_hash }
      before { transaction.stub(:exception? => false) }

      context "with an exception request" do
        before { transaction.stub(:exception? => true) }

        it "calls TransactionFormatter.faulty with self" do
          formatter.should_receive(:faulty).with(transaction).and_return({})
        end
      end

      context "with a slow request" do
        before { transaction.stub(:slow_request? => true) }

        it "calls TransactionFormatter.slow with self" do
          formatter.should_receive(:slow).with(transaction).and_return({})
        end
      end

      context "with a regular request" do
        before { transaction.stub(:slow_request? => false) }

        it "calls TransactionFormatter.slow with self" do
          formatter.should_receive(:regular).with(transaction).and_return({})
        end
      end

      after { subject }
    end

    describe '#complete!' do
      let(:event) { mock(:event) }
      before { transaction.set_process_action_event(notification_event) }

      it 'should remove transaction from the list' do
        expect { transaction.complete! }.
          to change(Appsignal.transactions, :length).by(-1)
      end

      context 'enqueueing' do
        context 'sanity check' do
          specify { Appsignal.should respond_to(:enqueue) }
        end

        context 'without events and without exception' do
          it 'should add transaction to the agent' do
            Appsignal.should_receive(:enqueue).with(transaction)
          end
        end

        context 'with events' do
          before { transaction.add_event(event) }

          it 'should add transaction to the agent' do
            Appsignal.should_receive(:enqueue).with(transaction)
          end
        end

        context 'with exception' do
          before { transaction.add_exception(event) }

          it 'should add transaction to the agent' do
            Appsignal.should_receive(:enqueue).with(transaction)
          end
        end

        after { transaction.complete! }
      end

      context 'thread' do
        before { transaction.complete! }

        it 'should reset the thread transaction id' do
          Thread.current[:appsignal_transaction_id].should be_nil
        end
      end
    end
  end
end
