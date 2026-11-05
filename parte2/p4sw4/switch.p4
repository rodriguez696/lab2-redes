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
    bit<72> other1;
    bit<8> protocol;
    bit<80> other2;
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
        pkt.extract(hdr.ipv4);
        pkt.extract(hdr.tcp);
        transition accept;
    }

    state parse_ipv4 {
        bit<32> fst_line = pkt.lookahead<bit<32>>();
	bit<16> size_in_bytes = fst_line[31:16];
        bit<32> size_in_bits = (bit<32>)size_in_bytes * 8;
        
        pkt.skip(32 + size_in_bits);
        transition parse_tcp;
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
    // TODO: completar por el grupo.

    apply {
        // TODO: completar por el grupo.
    }
}

/*************************************************************************
 *  Egress
 *************************************************************************/
control MyEgress(inout headers_t hdr,
                 inout metadata_t meta,
                 inout standard_metadata_t std_meta) {
    apply {
        // TODO: completar por el grupo (si corresponde).
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
