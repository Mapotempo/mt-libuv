module Libuv
    module Ext
        # blksize_t, in_addr_t is not yet part of types.conf on linux
        typedef :long, :blksize_t
        typedef :uint32, :in_addr_t
        typedef :ushort, :in_port_t


        class Sockaddr < FFI::Struct
            layout :sa_family, :sa_family_t,
                   :sa_data, [:char, 14]
        end

        class InAddr < FFI::Struct
            layout :s_addr, :in_addr_t
        end

        class SockaddrIn < FFI::Struct
            layout :sin_family, :sa_family_t,
                   :sin_port, :in_port_t,
                   :sin_addr, InAddr,
                   :sin_zero, [:char, 8]
        end

        class U6Addr < FFI::Union
            layout :__u6_addr8, [:uint8, 16],
                   :__u6_addr16, [:uint16, 8]
        end

        class In6Addr < FFI::Struct
            layout :__u6_addr, U6Addr
        end

        class SockaddrIn6 < FFI::Struct
            layout :sin6_family, :sa_family_t,
                   :sin6_port, :in_port_t,
                   :sin6_flowinfo, :uint32,
                   :sin6_addr, In6Addr,
                   :sin6_scope_id, :uint32
        end

        class UvAddrinfo < FFI::Struct
            layout  :flags, :int,
                    :family, :int,
                    :socktype, :int,
                    :protocol, :int,
                    :addrlen, :socklen_t,
                    :addr, Sockaddr.by_ref,
                    :canonname, :string,
                    :next, UvAddrinfo.by_ref
        end
    end
end