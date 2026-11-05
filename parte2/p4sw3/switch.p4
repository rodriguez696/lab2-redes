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

struct headers_t {
    ethernet_t ethernet;
}

struct metadata_t { }

/*************************************************************************
 *  Parser
 *************************************************************************/
parser MyParser(packet_in pkt,
                out headers_t hdr,
                inout metadata_t meta,
                inout standard_metadata_t std_meta) {
    state start {
        pkt.extract(hdr.ethernet);
        transition accept;
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
   

    direct_counter(CounterType.packets) paquetes_puerto;
    counter(1, CounterType.packets) paquetes_descartados;

    action fwd(bit<9> port) {
        std_meta.egress_spec = port;
    }

    action broadcast() {
        std_meta.mcast_grp = 3;
    }

    action drop() {
        mark_to_drop(std_meta);
    }

    action filter() {
        // capa 2:
        // Si protocolo es ARP, dejar pasar
        if (hdr.ethernet.etherType == 16w0x0806) {} 
        // si puerto de salida no lleva a GW, mark_to_drop
        else if (std_meta.egress_spec != 1) {
            mark_to_drop(std_meta);
            paquetes_descartados.count(0);
        }
        // capa3:
        // si ip destino es otra cosa que servidor y puerto no es 80 o 445, mark_to_drop
    }

    table smac {
        key = { hdr.ethernet.srcAddr : exact; }

        actions = {
            filter; 
            NoAction;
        }

        default_action = NoAction;
        size = 4096;
    }

    table dmac {
        key = { hdr.ethernet.dstAddr : exact; }

        actions = {
            fwd;
            broadcast;
            drop;
        }

        counters = paquetes_puerto;

        default_action = broadcast;
        size = 4096;
    }

    apply {
        dmac.apply();
        smac.apply();
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
