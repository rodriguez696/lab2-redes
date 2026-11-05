/* Obligatorio 2 - Parte 2: esqueleto del switch P4 (v1model / BMv2).
 *
 * Provisto por el curso: definicion del encabezado Ethernet, parser y
 * deparser. El resto de la logica debe ser implementada por el grupo.
 */
#include <core.p4>
#include <v1model.p4>

/*************************************************************************
 *  Encabezados
 *************************************************************************/
header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

//Cabeceras de TCP son de 20B
header tcp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<128> other; //No nos interesa
}

//Dado que bits se leen secuencialmente, necesitamos ignorar bits de capa de red (salvo campo Protocolo)
header ipv4_t {
    bit<16> other1;
    bit<16> size_in_bytes;
    bit<40> other2;
    bit<8> protocol;
    bit<80> other3;
}

struct headers_t {
    ethernet_t ethernet;
    ipv4_t ipv4;
    tcp_t tcp;
}

struct metadata_t {
}

/*************************************************************************
 *  Parser
 *************************************************************************/
parser MyParser(packet_in pkt,
                out headers_t hdr,
                inout metadata_t meta,
                inout standard_metadata_t std_meta) {
    state start {
        pkt.extract(hdr.ethernet);
        
        transition parse_ipv4;
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);

        bit<32> size_in_bits = (bit<32>)ipv4.size_in_bytes * 8;

        if(ipv4.protocol != 8w0x06){
            transition reject;
        }

        if(size_in_bits > 32w160){
            pkt.skip(size_in_bits - 32w160);
        }

        transition parse_tcp;
    }

    state parse_tcp{
        pkt.extract(hdr.tcp);

        if(tcp.dstPort == 80 || tcp.dstPort == 443){
            transition accept;
        }

        transition reject;
    }
}

/*************************************************************************
 *  Verificacion de checksum
 *************************************************************************/
control MyVerifyChecksum(inout headers_t hdr, inout metadata_t meta) {
    apply { }
}

/*************************************************************************
 *  Ingress
 *************************************************************************/

control MyIngress(inout headers_t hdr,
                  inout metadata_t meta,
                  inout standard_metadata_t std_meta) {
   

    direct_counter(CounterType.packets) my_direct_counter;

    action fwd(bit<9> port) {
        std_meta.egress_spec = port;
    }

    action broadcast() {
        std_meta.mcast_grp = 4; 
    }

    action drop() {
        mark_to_drop(std_meta);
    }

    table dmac {
        key = { hdr.ethernet.dstAddr : exact; }

        actions = {
            fwd;
            broadcast;
            drop;
        }

        counters = my_direct_counter;

        default_action = broadcast;
        size = 4096;
    }

    apply {
        dmac.apply();
    }
}

/*************************************************************************
 *  Egress
 *************************************************************************/
control MyEgress(inout headers_t hdr,
                 inout metadata_t meta,
                 inout standard_metadata_t std_meta) {
    apply {
	if(std_meta.egress_port == std_meta.ingress_port){
                mark_to_drop(std_meta);
        }
    }
}

/*************************************************************************
 *  Calculo de checksum
 *************************************************************************/
control MyComputeChecksum(inout headers_t hdr, inout metadata_t meta) {
    apply { }
}

/*************************************************************************
 *  Deparser
 *************************************************************************/
control MyDeparser(packet_out pkt, in headers_t hdr) {
    apply {
        pkt.emit(hdr.ethernet);
    }
}

V1Switch(MyParser(),
         MyVerifyChecksum(),
         MyIngress(),
         MyEgress(),
         MyComputeChecksum(),
         MyDeparser()) main;
