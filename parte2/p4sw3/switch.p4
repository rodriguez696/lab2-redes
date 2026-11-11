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
    bit<4> other1;
    bit<4> size_in_bytes;
    bit<64> other2;
    bit<8> protocol;
    bit<16> checksum;
    bit<32> srcIP;
    bit<32> dstIP;
}

struct headers_t {
    ethernet_t ethernet;
    ipv4_t ipv4;
    tcp_t tcp;
}

struct metadata_t { }

/**************************************************************************
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

        bit<32> size_in_bits = (bit<32>)hdr.ipv4.size_in_bytes * 8;

        if(size_in_bits > 32w160) {
           pkt.advance(size_in_bits - 32w160);
        }

        transition select(hdr.ipv4.protocol){
            8w0x06: parse_tcp;
            default: accept;
        }

    }

    state parse_tcp {
        pkt.extract(hdr.tcp);

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
    counter(1, CounterType.packets) paquetes_descartados__switch_port;
    counter(1, CounterType.packets) paquetes_descartados__invalid_traffic;

    action fwd(bit<9> port) {
        std_meta.egress_spec = port;
    }

    action broadcast() {
        std_meta.mcast_grp = 3;
    }

    action drop() {
        mark_to_drop(std_meta);
    }

    action filter(bit<9> port, bit<32> ipGw, bit<32> ipDest) {
        // Si protocolo es ARP, dejar pasar
        if (hdr.ethernet.etherType == 16w0x0806) { 
	// Si el protocolo indicado en la trama no es ARP o IP, descartar
	}else if (hdr.ethernet.etherType != 16w0x0800) {
	    mark_to_drop(std_meta);
	    paquetes_descartados__invalid_traffic.count(0);
	// si puerto de salida no lleva a GW, mark_to_drop
	}else if (std_meta.egress_spec != port) {
            mark_to_drop(std_meta);
            paquetes_descartados_switch_port.count(0);
	// Si dentro del paquete IP, el trafico generado es o bien un datagrama dirigido a una subred distinta de
	// SERVERS, o bien es un segmento que no use TCP o lo use pero en puertos distintos a 80/443, descartar
        } else if (hdr.ipv4.dstIP != ipGw && 
		   (hdr.ipv4.dstIP != ipDest || (hdr.ipv4.protocol != 0x6 ||
		   (hdr.tcp.dstPort != 16w80 && hdr.tcp.dstPort != 16w443)))) {
            mark_to_drop(std_meta);
            paquetes_descartados__invalid_traffic.count(0);
        }
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

        default_action = drop; 
        size = 4096;
    }

    apply {
	if (std_meta.parser_error != error.NoError) {
	    mark_to_drop(std_meta);
	else {
            dmac.apply();
            smac.apply();
	}
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
        pkt.emit(hdr.ipv4);
        pkt.emit(hdr.tcp);
    }
}

V1Switch(MyParser(),
         MyVerifyChecksum(),
         MyIngress(),
         MyEgress(),
         MyComputeChecksum(),
         MyDeparser()) main;
