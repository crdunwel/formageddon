module Formageddon
  class ThreadsController < ApplicationController
    def new
      @contact_steps = FormageddonContactStep.where(["formageddon_recipient_id=? AND formageddon_recipient_type=?",
                                                     params[:recipient_id], params[:recipient_type]])

      if @contact_steps.empty?
        flash[:error] = "Contact process has not been configured for recipient."
        redirect_to "/"
      end

      recipient = Object.const_get(params[:recipient_type]).find_by_id(params[:recipient_id])

      @formageddon_thread = FormageddonThread.new
      @formageddon_thread.formageddon_recipient = recipient
      @formageddon_thread.formageddon_letters.build

      # check for user
      begin
        user = self.send(Formageddon::configuration.user_method)
        if user
          @formageddon_thread.attributes.keys.each do |k|
            if u_method = Formageddon::configuration.sender_user_mapping[k.to_sym]
              begin
                @formageddon_thread.send("#{k}=", user.send(u_method))
              rescue
              end
            end
          end
        end
      rescue
      end
    end

    def create
      formageddon_params = params[:formageddon]
      multi_recipients = formageddon_params[:formageddon_multi_recipients]

      threads = []

      if multi_recipients.nil?
        thread = FormageddonThread.new(params[:formageddon_formageddon_thread])
        set_user_for_thread(thread)
        threads << thread
      else
        multi_recipients.keys.each do |k|
          object = multi_recipients[k]
          recipient = Object.const_get(object).find_by_id(k)
          if recipient
            thread = recipient.formageddon_threads.build(params[:formageddon_formageddon_thread])
            set_user_for_thread(thread)
            threads << thread
          end
        end
      end

      passed_validation = true
      threads.each do |t|
        passed_validation = false unless t.save
      end

      if passed_validation
        # check to see if there is a no sender URL. this means a sender is required
        unless formageddon_params[:no_sender_redirect].blank?
          if threads.first.formageddon_sender.nil?
            # we need to save the letter ids in the session and redirect
            session[:formageddon_unsent_threads] = threads.map(&:id)
            session[:formageddon_params] = formageddon_params
            respond_to do |format|
              format.html { redirect_to formageddon_params[:no_sender_redirect] }
              format.js { @redirect = formageddon_params[:no_sender_redirect] }
            end

            return
          end
        end

        threads.each do |t|
          t.formageddon_letters.first.update_attribute(:status, 'START')
          t.formageddon_letters.first.update_attribute(:direction, 'TO_RECIPIENT')

          if defined? Delayed
            t.formageddon_letters.first.delay.send_letter
          else
            t.formageddon_letters.first.send_letter
          end
        end

        letter_ids = threads.collect{|t| t.formageddon_letters.first.id}.join(',')

        session[:formageddon_after_send_url] = "#{formageddon_params[:after_send_url]}&letter_ids=#{letter_ids}" unless formageddon_params[:after_send_url].blank?

        respond_to do |format|
          format.html {
            redirect_to :controller => 'delivery_attempts', :action => 'show',
                        :letter_ids => letter_ids
          }
          format.js {
            redirect_to :controller => 'delivery_attempts', :action => 'show', :format => 'js',
                        :letter_ids => letter_ids
          }
        end

      else
        @formageddon_thread = threads.first
      end
    end


    def show
      @formageddon_thread = FormageddonThread.find(params[:id])
    end

    private

    def set_user_for_thread(thread)
      begin
        user = self.send(Formageddon::configuration.user_method)
        if user
          thread.formageddon_sender = user
        end
      rescue
      end
    end
  end
end