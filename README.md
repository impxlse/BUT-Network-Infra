# Conception et mise en œuvre d’une infrastructure réseau sécurisée à l’aide d’outils open-source

## Objectif
L'objectif de ce projet est de concevoir et de mettre en œuvre une infrastructure de réseau sécurisée qui peut protéger le réseau et les données d’une organisation contre les cybermenaces courantes. L’infrastructure de réseau doit être conçue pour fournir une communication, un contrôle d’accès et une surveillance sécurisés.

## Portée
- L’infrastructure doit être construite en utilisant Linux, des logiciels libres et des machines virtuelles.
- Elle doit inclure des solutions de pare-feu, de DNS, de DHCP et de surveillance du réseau.
- Configuration pour prendre en charge la journalisation et la surveillance avec un serveur de logs dédié.
- Configuration pour prendre en charge les communications sécurisées utilisant SSL/TLS.
- Évolutivité et facilité de gestion.
- Infrastructure réseau avec des commutateurs virtuels, des routeurs virtuels et des réseaux virtuels.
- Prévoir des machines avec un accès limité aux services réseau et des machines d’administrateurs.
- Une ou plusieurs DMZ pour isoler certains serveurs ayant des services spécifiques.

## Outils (par ordre d’importance)
- OS Serveurs : Ubuntu ou Debian
- Postes de travail : Ubuntu ou Debian
- Virtualisation : QEMU / KVM
- DHCP : ISC DHCPD
- DNS (domaine interne pas forcément visible de l’extérieur) : BIND9
- Annuaire LDAP : OpenLDAP (avec extension LDAPS)
- Pare-feu : iptables ou nftables
- Journalisation : rsyslogd, systemd-journald
- Surveillance du réseau : Nagios ou Zabbix ou Centreon
- Serveur de fichier : Samba ou NFS
- Web avec SSL/TLS : Apache / OpenSSL
- Intranet (avec authentification) : Apache / OpenSSL
- Serveurs SGBD séparés des serveurs web

## Livrables
1. Document de conception détaillé incluant l’architecture, les considérations de sécurité, et une liste des logiciels choisis avec argumentation et comparaison.
2. Prototype fonctionnel.
3. Procédure complète de test avec scripts utilisables par un informaticien non spécialisé.
4. Scripts pour automatiser la configuration des machines fournissant les services réseau.
5. Documentation technique décrivant les étapes de chaque script.
6. Présentation montrant la réalisation et l’écart au document de conception initial.
