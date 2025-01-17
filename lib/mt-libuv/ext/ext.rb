# frozen_string_literal: true

require 'forwardable'
require 'ffi'

module MTLibuv
    module Ext
        extend Forwardable
        extend FFI::Library
        FFI::DEBUG = 10


        # In windows each library requires its own module
        module LIBC
            extend FFI::Library
            ffi_lib(FFI::Library::LIBC).first

            attach_function :malloc, [:size_t], :pointer
            attach_function :free, [:pointer], :void
        end

        def self.malloc(bytes)
            ::MTLibuv::Ext::LIBC.malloc(bytes)
        end

        def self.free(pointer)
            ::MTLibuv::Ext::LIBC.free(pointer)
        end


        def self.path_to_internal_libuv
            @path_to_internal_libuv ||= ::File.expand_path("../../../../ext/libuv/lib/libuv.#{FFI::Platform::LIBSUFFIX}", __FILE__)
        end


        begin
            lib_path = ::File.expand_path('../', path_to_internal_libuv)

            # bias the library discovery to a path inside the gem first, then
            # to the usual system paths
            paths = [
                lib_path,
                '/usr/local/lib',
                '/opt/local/lib',
                '/usr/lib64'
            ]

            if FFI::Platform.mac?
                # Using home/user/lib is the best we can do on OSX
                # Primarily a dev platform so that is OK
                paths.unshift "#{ENV['HOME']}/lib"
                LIBUV_PATHS = paths.map{|path| "#{path}/libuv.1.#{FFI::Platform::LIBSUFFIX}"}
            else
                LIBUV_PATHS = paths.map{|path| "#{path}/libuv.#{FFI::Platform::LIBSUFFIX}"}
                if FFI::Platform.windows?
                    module Kernel32
                        extend FFI::Library
                        ffi_lib 'Kernel32'

                        attach_function :add_dll_dir, :AddDllDirectory,
                            [ :buffer_in ], :pointer
                    end
                    # This ensures that externally loaded libraries like the libcouchbase gem
                    # will always use the same binary image and not load a second into memory
                    Kernel32.add_dll_dir "#{lib_path}\0".encode("UTF-16LE")
                else # UNIX
                    # TODO:: ??
                end
            end

            libuv = ffi_lib(LIBUV_PATHS + %w{libuv}).first
        rescue LoadError
            warn <<-WARNING
            Unable to load this gem. The libuv library (or DLL) could not be found.
            If this is a Windows platform, make sure libuv.dll is on the PATH.
            For non-Windows platforms, make sure libuv is located in this search path:
            #{LIBUV_PATHS.inspect}
            WARNING
            exit 255
        end


        require 'mt-libuv/ext/types'


        attach_function :handle_size, :uv_handle_size, [:uv_handle_type], :size_t
        attach_function :req_size, :uv_req_size, [:uv_req_type], :size_t


        # We need to calculate where the FS request data is located using req_size
        class FsRequest < FFI::Struct
            layout :req_data, [:uint8, Ext.req_size(:req)],
                   :fs_type, :uv_fs_type,
                   :loop, :uv_loop_t,
                   :fs_callback, :pointer,
                   :result, :ssize_t,
                   :ptr, :pointer,
                   :path, :string,
                   :stat, UvStat
        end
        callback :uv_fs_cb, [FsRequest.by_ref], :void


        attach_function :version_number, :uv_version, [], :uint
        attach_function :version_string, :uv_version_string, [], :string
        attach_function :loop_alive, :uv_loop_alive, [:uv_loop_t], :int

        attach_function :loop_size, :uv_loop_size, [], :size_t, :blocking => false
        attach_function :loop_init, :uv_loop_init, [:uv_loop_t], :int, :blocking => false
        attach_function :loop_close, :uv_loop_close, [:uv_loop_t], :int, :blocking => false

        attach_function :loop_new, :uv_loop_new, [], :uv_loop_t, :blocking => true
        attach_function :loop_delete, :uv_loop_delete, [:uv_loop_t], :void, :blocking => true
        attach_function :default_loop, :uv_default_loop, [], :uv_loop_t, :blocking => true
        attach_function :run, :uv_run, [:uv_loop_t, :uv_run_mode], :int, :blocking => true
        attach_function :stop, :uv_stop, [:uv_loop_t], :void, :blocking => true
        attach_function :update_time, :uv_update_time, [:uv_loop_t], :void, :blocking => true
        attach_function :now, :uv_now, [:uv_loop_t], :uint64

        attach_function :backend_timeout, :uv_backend_timeout, [:uv_loop_t], :int, :blocking => true
        attach_function :backend_fd, :uv_backend_fd, [:uv_loop_t], :int, :blocking => true

        attach_function :strerror, :uv_strerror, [:int], :string
        attach_function :err_name, :uv_err_name, [:int], :string

        attach_function :ref, :uv_ref, [:uv_handle_t], :void
        attach_function :unref, :uv_unref, [:uv_handle_t], :void
        attach_function :has_ref, :uv_has_ref, [:uv_handle_t], :int
        attach_function :is_active, :uv_is_active, [:uv_handle_t], :int
        attach_function :walk, :uv_walk, [:uv_loop_t, :uv_walk_cb, :pointer], :void, :blocking => true
        attach_function :close, :uv_close, [:uv_handle_t, :uv_close_cb], :void, :blocking => true
        attach_function :is_closing, :uv_is_closing, [:uv_handle_t], :int, :blocking => true
        # TODO:: Implement https://github.com/joyent/libuv/commit/0ecee213eac91beca141130cff2c7826242dab5a
        # uv_recv_buffer_size
        # uv_send_buffer_size
        # https://github.com/joyent/libuv/commit/4ca9a363897cfa60f4e2229e4f15ac5abd7fd103
        # uv_fileno

        attach_function :buf_init, :uv_buf_init, [:pointer, :size_t], UvBuf.by_value

        attach_function :listen, :uv_listen, [:uv_stream_t, :int, :uv_connection_cb], :int, :blocking => true
        attach_function :accept, :uv_accept, [:uv_stream_t, :uv_stream_t], :int, :blocking => true
        attach_function :read_start, :uv_read_start, [:uv_stream_t, :uv_alloc_cb, :uv_read_cb], :int, :blocking => true
        attach_function :read_stop, :uv_read_stop, [:uv_stream_t], :int, :blocking => true
        attach_function :try_write, :uv_try_write, [:uv_stream_t, :pointer, :uint], :int, :blocking => true
        attach_function :write, :uv_write, [:uv_write_t, :uv_stream_t, :pointer, :uint, :uv_write_cb], :int, :blocking => true
        attach_function :write2, :uv_write2, [:uv_write_t, :uv_stream_t, :pointer, :uint, :uv_stream_t, :uv_write_cb], :int, :blocking => true
        attach_function :is_readable, :uv_is_readable, [:uv_stream_t], :int, :blocking => true
        attach_function :is_writable, :uv_is_writable, [:uv_stream_t], :int, :blocking => true
        attach_function :shutdown, :uv_shutdown, [:uv_shutdown_t, :uv_stream_t, :uv_shutdown_cb], :int, :blocking => true

        attach_function :tcp_init, :uv_tcp_init, [:uv_loop_t, :uv_tcp_t], :int, :blocking => true
        attach_function :tcp_init_ex, :uv_tcp_init_ex, [:uv_loop_t, :uv_tcp_t, :uint], :int, :blocking => true
        attach_function :tcp_open, :uv_tcp_open, [:uv_tcp_t, :uv_os_sock_t], :int, :blocking => true
        attach_function :tcp_nodelay, :uv_tcp_nodelay, [:uv_tcp_t, :int], :int, :blocking => true
        attach_function :tcp_keepalive, :uv_tcp_keepalive, [:uv_tcp_t, :int, :uint], :int, :blocking => true
        attach_function :tcp_simultaneous_accepts, :uv_tcp_simultaneous_accepts, [:uv_tcp_t, :int], :int, :blocking => true
        attach_function :tcp_bind, :uv_tcp_bind, [:uv_tcp_t, :sockaddr_in, :uint], :int, :blocking => true
        attach_function :tcp_getsockname, :uv_tcp_getsockname, [:uv_tcp_t, :pointer, :pointer], :int, :blocking => true
        attach_function :tcp_getpeername, :uv_tcp_getpeername, [:uv_tcp_t, :pointer, :pointer], :int, :blocking => true
        attach_function :tcp_connect, :uv_tcp_connect, [:uv_connect_t, :uv_tcp_t, :sockaddr_in, :uv_connect_cb], :int, :blocking => true

        attach_function :udp_init, :uv_udp_init, [:uv_loop_t, :uv_udp_t], :int, :blocking => true
        attach_function :udp_init_ex, :uv_udp_init_ex, [:uv_loop_t, :uv_udp_t, :uint], :int, :blocking => true
        attach_function :udp_open, :uv_udp_open, [:uv_udp_t, :uv_os_sock_t], :int, :blocking => true
        attach_function :udp_bind, :uv_udp_bind, [:uv_udp_t, :sockaddr_in, :uint], :int, :blocking => true
        attach_function :udp_getsockname, :uv_udp_getsockname, [:uv_udp_t, :pointer, :pointer], :int, :blocking => true
        attach_function :udp_set_membership, :uv_udp_set_membership, [:uv_udp_t, :string, :string, :uv_membership], :int, :blocking => true
        attach_function :udp_set_multicast_loop, :uv_udp_set_multicast_loop, [:uv_udp_t, :int], :int, :blocking => true
        attach_function :udp_set_multicast_ttl, :uv_udp_set_multicast_ttl, [:uv_udp_t, :int], :int, :blocking => true
        attach_function :udp_set_broadcast, :uv_udp_set_broadcast, [:uv_udp_t, :int], :int, :blocking => true
        attach_function :udp_set_ttl, :uv_udp_set_ttl, [:uv_udp_t, :int], :int, :blocking => true
        attach_function :udp_try_send, :uv_udp_try_send, [:uv_udp_t, :pointer, :int, :sockaddr_in], :int, :blocking => true
        attach_function :udp_send, :uv_udp_send, [:uv_udp_send_t, :uv_udp_t, :pointer, :int, :sockaddr_in, :uv_udp_send_cb], :int, :blocking => true
        attach_function :udp_recv_start, :uv_udp_recv_start, [:uv_udp_t, :uv_alloc_cb, :uv_udp_recv_cb], :int, :blocking => true
        attach_function :udp_recv_stop, :uv_udp_recv_stop, [:uv_udp_t], :int, :blocking => true

        attach_function :tty_init, :uv_tty_init, [:uv_loop_t, :uv_tty_t, :uv_file, :int], :int, :blocking => true
        attach_function :tty_set_mode, :uv_tty_set_mode, [:uv_tty_t, :int], :int, :blocking => true
        attach_function :tty_reset_mode, :uv_tty_reset_mode, [], :void, :blocking => true
        attach_function :tty_get_winsize, :uv_tty_get_winsize, [:uv_tty_t, :pointer, :pointer], :int, :blocking => true

        attach_function :guess_handle, :uv_guess_handle, [:uv_file], :uv_handle_type, :blocking => true

        attach_function :pipe_init, :uv_pipe_init, [:uv_loop_t, :uv_pipe_t, :int], :int, :blocking => true
        attach_function :pipe_open, :uv_pipe_open, [:uv_pipe_t, :uv_file], :void, :blocking => true
        attach_function :pipe_bind, :uv_pipe_bind, [:uv_pipe_t, :string], :int, :blocking => true
        attach_function :pipe_connect, :uv_pipe_connect, [:uv_connect_t, :uv_pipe_t, :string, :uv_connect_cb], :void, :blocking => true
        attach_function :pipe_pending_instances, :uv_pipe_pending_instances, [:uv_pipe_t, :int], :void, :blocking => true
        attach_function :pipe_pending_count, :uv_pipe_pending_count, [:uv_pipe_t], :int, :blocking => true
        attach_function :pipe_pending_type, :uv_pipe_pending_type, [:uv_pipe_t], :uv_handle_type, :blocking => true
        attach_function :pipe_getsockname, :uv_pipe_getsockname, [:uv_pipe_t, :pointer, :pointer], :int, :blocking => true
        attach_function :pipe_getpeername, :uv_pipe_getpeername, [:uv_pipe_t, :pointer, :pointer], :int, :blocking => true

        attach_function :prepare_init, :uv_prepare_init, [:uv_loop_t, :uv_prepare_t], :int, :blocking => true
        attach_function :prepare_start, :uv_prepare_start, [:uv_prepare_t, :uv_prepare_cb], :int, :blocking => true
        attach_function :prepare_stop, :uv_prepare_stop, [:uv_prepare_t], :int, :blocking => true

        attach_function :check_init, :uv_check_init, [:uv_loop_t, :uv_check_t], :int, :blocking => true
        attach_function :check_start, :uv_check_start, [:uv_check_t, :uv_check_cb], :int, :blocking => true
        attach_function :check_stop, :uv_check_stop, [:uv_check_t], :int, :blocking => true

        attach_function :idle_init, :uv_idle_init, [:uv_loop_t, :uv_idle_t], :int, :blocking => true
        attach_function :idle_start, :uv_idle_start, [:uv_idle_t, :uv_idle_cb], :int, :blocking => true
        attach_function :idle_stop, :uv_idle_stop, [:uv_idle_t], :int, :blocking => true

        attach_function :async_init, :uv_async_init, [:uv_loop_t, :uv_async_t, :uv_async_cb], :int, :blocking => true
        attach_function :async_send, :uv_async_send, [:uv_async_t], :int, :blocking => true

        attach_function :timer_init, :uv_timer_init, [:uv_loop_t, :uv_timer_t], :int, :blocking => true
        attach_function :timer_start, :uv_timer_start, [:uv_timer_t, :uv_timer_cb, :int64_t, :int64_t], :int, :blocking => true
        attach_function :timer_stop, :uv_timer_stop, [:uv_timer_t], :int, :blocking => true
        attach_function :timer_again, :uv_timer_again, [:uv_timer_t], :int, :blocking => true
        attach_function :timer_set_repeat, :uv_timer_set_repeat, [:uv_timer_t, :int64_t], :void, :blocking => true
        attach_function :timer_get_repeat, :uv_timer_get_repeat, [:uv_timer_t], :int64_t, :blocking => true
        #:addrinfo
        attach_function :getaddrinfo, :uv_getaddrinfo, [:uv_loop_t, :uv_getaddrinfo_t, :uv_getaddrinfo_cb, :string, :string, UvAddrinfo.by_ref], :int
        attach_function :freeaddrinfo, :uv_freeaddrinfo, [UvAddrinfo.by_ref], :void

        attach_function :spawn, :uv_spawn, [:uv_loop_t, :uv_process_t, UvProcessOptions.by_ref], :int, :blocking => true
        attach_function :process_kill, :uv_process_kill, [:uv_process_t, :int], :int, :blocking => true
        attach_function :kill, :uv_kill, [:int, :int], :int, :blocking => true
        attach_function :queue_work, :uv_queue_work, [:uv_loop_t, :uv_work_t, :uv_work_cb, :uv_after_work_cb], :int, :blocking => true
        attach_function :cancel, :uv_cancel, [:pointer], :int, :blocking => true
        attach_function :setup_args, :uv_setup_args, [:int, :varargs], :pointer, :blocking => true
        attach_function :get_process_title, :uv_get_process_title, [:pointer, :size_t], :int, :blocking => true
        attach_function :set_process_title, :uv_set_process_title, [:string], :int, :blocking => true
        attach_function :resident_set_memory, :uv_resident_set_memory, [:size_t], :int, :blocking => true

        attach_function :uptime, :uv_uptime, [:pointer], :int, :blocking => true
        attach_function :cpu_info, :uv_cpu_info, [:uv_cpu_info_t, :pointer], :int, :blocking => true
        attach_function :loadavg, :uv_loadavg, [:pointer], :void, :blocking => true
        attach_function :free_cpu_info, :uv_free_cpu_info, [:uv_cpu_info_t, :int], :void, :blocking => true
        attach_function :interface_addresses, :uv_interface_addresses, [:uv_interface_address_t, :pointer], :int, :blocking => true
        attach_function :free_interface_addresses, :uv_free_interface_addresses, [:uv_interface_address_t, :int], :void, :blocking => true

        attach_function :fs_req_cleanup, :uv_fs_req_cleanup, [:uv_fs_t], :void, :blocking => true
        attach_function :fs_close, :uv_fs_close, [:uv_loop_t, :uv_fs_t, :uv_file, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_open, :uv_fs_open, [:uv_loop_t, :uv_fs_t, :string, :int, :int, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_read, :uv_fs_read, [:uv_loop_t, :uv_fs_t, :uv_file, :pointer, :uint, :off_t, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_unlink, :uv_fs_unlink, [:uv_loop_t, :uv_fs_t, :string, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_write, :uv_fs_write, [:uv_loop_t, :uv_fs_t, :uv_file, :pointer, :uint, :off_t, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_mkdir, :uv_fs_mkdir, [:uv_loop_t, :uv_fs_t, :string, :int, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_rmdir, :uv_fs_rmdir, [:uv_loop_t, :uv_fs_t, :string, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_readdir, :uv_fs_scandir, [:uv_loop_t, :uv_fs_t, :string, :int, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_readdir_next, :uv_fs_scandir_next, [:uv_fs_t, :uv_dirent_t], :int, :blocking => true
        attach_function :fs_stat, :uv_fs_stat, [:uv_loop_t, :uv_fs_t, :string, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_fstat, :uv_fs_fstat, [:uv_loop_t, :uv_fs_t, :uv_file, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_rename, :uv_fs_rename, [:uv_loop_t, :uv_fs_t, :string, :string, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_fsync, :uv_fs_fsync, [:uv_loop_t, :uv_fs_t, :uv_file, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_fdatasync, :uv_fs_fdatasync, [:uv_loop_t, :uv_fs_t, :uv_file, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_ftruncate, :uv_fs_ftruncate, [:uv_loop_t, :uv_fs_t, :uv_file, :off_t, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_sendfile, :uv_fs_sendfile, [:uv_loop_t, :uv_fs_t, :uv_file, :uv_file, :off_t, :size_t, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_chmod, :uv_fs_chmod, [:uv_loop_t, :uv_fs_t, :string, :int, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_utime, :uv_fs_utime, [:uv_loop_t, :uv_fs_t, :string, :double, :double, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_futime, :uv_fs_futime, [:uv_loop_t, :uv_fs_t, :uv_file, :double, :double, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_access, :uv_fs_access, [:uv_loop_t, :uv_fs_t, :string, :int, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_lstat, :uv_fs_lstat, [:uv_loop_t, :uv_fs_t, :string, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_link, :uv_fs_link, [:uv_loop_t, :uv_fs_t, :string, :string, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_symlink, :uv_fs_symlink, [:uv_loop_t, :uv_fs_t, :string, :string, :int, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_readlink, :uv_fs_readlink, [:uv_loop_t, :uv_fs_t, :string, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_fchmod, :uv_fs_fchmod, [:uv_loop_t, :uv_fs_t, :uv_file, :int, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_chown, :uv_fs_chown, [:uv_loop_t, :uv_fs_t, :string, :int, :int, :uv_fs_cb], :int, :blocking => true
        attach_function :fs_fchown, :uv_fs_fchown, [:uv_loop_t, :uv_fs_t, :uv_file, :int, :int, :uv_fs_cb], :int, :blocking => true

        attach_function :fs_event_init, :uv_fs_event_init, [:uv_loop_t, :uv_fs_event_t, :string, :uv_fs_event_cb, :int], :int, :blocking => true

        attach_function :ip4_addr, :uv_ip4_addr, [:string, :int, :sockaddr_in4], :int
        attach_function :ip6_addr, :uv_ip6_addr, [:string, :int, :sockaddr_in6], :int
        attach_function :ip4_name, :uv_ip4_name, [:sockaddr_in4, :pointer, :size_t], :int
        attach_function :ip6_name, :uv_ip6_name, [:sockaddr_in6, :pointer, :size_t], :int
        #TODO:: attach_function :inet_ntop, :uv_inet_ntop, [:int, :pointer, ]
        #TODO:: attach_function :uv_inet_pton

        attach_function :exepath, :uv_exepath, [:pointer, :size_t], :int, :blocking => true
        attach_function :cwd, :uv_cwd, [:pointer, :size_t], :int, :blocking => true
        attach_function :chdir, :uv_chdir, [:string], :int, :blocking => true
        attach_function :get_free_memory, :uv_get_free_memory, [], :uint64, :blocking => true
        attach_function :get_total_memory, :uv_get_total_memory, [], :uint64, :blocking => true
        attach_function :hrtime, :uv_hrtime, [], :uint64, :blocking => true
        attach_function :disable_stdio_inheritance, :uv_disable_stdio_inheritance, [], :void, :blocking => true
        attach_function :dlopen, :uv_dlopen, [:string, :uv_lib_t], :int, :blocking => true
        attach_function :dlclose, :uv_dlclose, [:uv_lib_t], :int, :blocking => true
        attach_function :dlsym, :uv_dlsym, [:uv_lib_t, :string, :pointer], :int, :blocking => true
        attach_function :dlerror, :uv_dlerror, [:uv_lib_t], :string

        attach_function :mutex_init, :uv_mutex_init, [:uv_mutex_t], :int, :blocking => true
        attach_function :mutex_destroy, :uv_mutex_destroy, [:uv_mutex_t], :void, :blocking => true
        attach_function :mutex_lock, :uv_mutex_lock, [:uv_mutex_t], :void, :blocking => true
        attach_function :mutex_trylock, :uv_mutex_trylock, [:uv_mutex_t], :int, :blocking => true
        attach_function :mutex_unlock, :uv_mutex_unlock, [:uv_mutex_t], :void, :blocking => true

        attach_function :signal_init, :uv_signal_init, [:uv_loop_t, :uv_signal_t], :int, :blocking => true
        attach_function :signal_start, :uv_signal_start, [:uv_signal_t, :uv_signal_cb, :int], :int, :blocking => true
        attach_function :signal_stop, :uv_signal_stop, [:uv_signal_t], :int, :blocking => true

        attach_function :rwlock_init, :uv_rwlock_init, [:uv_rwlock_t], :int, :blocking => true
        attach_function :rwlock_destroy, :uv_rwlock_destroy, [:uv_rwlock_t], :void, :blocking => true
        attach_function :rwlock_rdlock, :uv_rwlock_rdlock, [:uv_rwlock_t], :void, :blocking => true
        attach_function :rwlock_tryrdlock, :uv_rwlock_tryrdlock, [:uv_rwlock_t], :int, :blocking => true
        attach_function :rwlock_rdunlock, :uv_rwlock_rdunlock, [:uv_rwlock_t], :void, :blocking => true
        attach_function :rwlock_wrlock, :uv_rwlock_wrlock, [:uv_rwlock_t], :void, :blocking => true
        attach_function :rwlock_trywrlock, :uv_rwlock_trywrlock, [:uv_rwlock_t], :int, :blocking => true
        attach_function :rwlock_wrunlock, :uv_rwlock_wrunlock, [:uv_rwlock_t], :void, :blocking => true

        attach_function :once, :uv_once, [:uv_once_t, :uv_cb], :void, :blocking => true
        attach_function :thread_create, :uv_thread_create, [:uv_thread_t, :uv_cb], :int, :blocking => true
        attach_function :thread_join, :uv_thread_join, [:uv_thread_t], :int, :blocking => true


        # Predetermine the handle sizes
        enum_type(:uv_handle_type).symbols.each do |handle_type|
            handle_size = Ext.handle_size(handle_type)
            define_singleton_method(:"allocate_handle_#{handle_type}") { ::MTLibuv::Ext::LIBC.malloc(handle_size) }
        end

        enum_type(:uv_req_type).symbols.each do |request_type|
            request_size = Ext.req_size(request_type)
            define_singleton_method(:"allocate_request_#{request_type}") { ::MTLibuv::Ext::LIBC.malloc(request_size) }
        end
    end
end
