# frozen_string_literal: true

module MTLibuv
    class Check < Handle


        define_callback function: :on_check


        # @param reactor [::MTLibuv::Reactor] reactor this check will be associated
        # @param callback [Proc] callback to be called on reactor check
        def initialize(reactor)
            @reactor = reactor

            check_ptr = ::MTLibuv::Ext.allocate_handle_check
            error = check_result(::MTLibuv::Ext.check_init(reactor.handle, check_ptr))

            super(check_ptr, error)
        end

        # Enables the check handler.
        def start
            return if @closed
            error = check_result ::MTLibuv::Ext.check_start(handle, callback(:on_check))
            reject(error) if error
            self
        end

        # Disables the check handler.
        def stop
            return if @closed
            error = check_result ::MTLibuv::Ext.check_stop(handle)
            reject(error) if error
            self
        end

        # Used to update the callback that will be triggered on reactor check
        #
        # @param callback [Proc] the callback to be called on reactor check
        def progress(&callback)
            @callback = callback
            self
        end


        private


        def on_check(handle)
            @reactor.exec do
                begin
                    @callback.call
                rescue Exception => e
                    @reactor.log e, 'performing check callback'
                end
            end
        end
    end
end