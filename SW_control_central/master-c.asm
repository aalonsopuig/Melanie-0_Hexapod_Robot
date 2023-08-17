; master-c
; Programa para control mediante bus i2c de los Slaves de Melanie (versión master)
; Por: Alejandro Alonso Puig
; Fecha: 24/4/2003
; Controlador: 16F876
; Función: 
; Trabaja como Master de Melanie
; Realiza transmisión bidireccional
; Asimismo controla el servo de la cabeza, aunque el programa está preparado 
; para gestionar hasta 3 servos.
; Controla también un sensor de distancia infrarrojo Sharp GP2D12



	list 		p=16F876
	include		"P16F876.INC"

;Definición de macros

	#define	ClockValue d'200' 	;(3,9khz) valor para cálculo de vel. I2C que pasará a SSPADD

	;Definiciones servos
	#define	Servo1	PORTA,1	;RA1 - Servo nº1
	#define	Servo2	PORTA,2	;RA2 - Servo nº2
	#define	Servo3	PORTA,3	;RA3 - Servo nº3
	#define	Offset1	d'60'	;Offset Servo nº1
	#define	Offset2	d'35'	;Offset Servo nº2
	#define	Offset3	d'34'	;Offset Servo nº3
	;El valor de Offset permite establecer la posición de cero grados en función 
	;de la anchura del pulso activo en microsegundos. El cálculo se hace mediante 
	;la fórmula Offset=(T-10)/5, donde T es la anchura del pulso activo en usg
	;Se utiliza para dos funciones: Ajustar varios servos para que sus ejes estén
	;colocados físicamente en la misma posición para cero grados, adaptando los
	;offsets de cada servo. También se utiliza para aprovechar al máximo el giro
	;posible del eje, que varia para cada marca y modelo.
	;Por ejemplo, si queremos establecer que el valor de 0º implique un pulso
	;activo de una anchura de 1000usg, el offset será (1000-10)/5=198

	;Direcciones de los Slaves
	#define	Broadcast	b'00000000' ;Dirección broadcast
	#define	D1		b'01110000' ;Dirección Slave correspondiente
	#define	D2		b'01110010' ;Dirección Slave correspondiente
	#define	D3		b'01110100' ;Dirección Slave correspondiente
	#define	I1		b'01110110' ;Dirección Slave correspondiente
	#define	I2		b'01111000' ;Dirección Slave correspondiente
	#define	I3		b'01111010' ;Dirección Slave correspondiente

	;Mensajes a enviar
	#define	NoHacerNada	d'00'	; No hacer nada
	#define	ArribaAlante	d'01'	; Subir pata adelante
	#define	ArribaAtras	d'02'	; Subir pata atras
	#define	AbajoAlante	d'03'	; Bajar pata
	#define	AbajoAtras	d'04'	; Bajar pata
	#define	SueloAlante	d'05'	; Desplazar pata adelante (pegada al suelo)
	#define	SueloAtras	d'06'	; Desplazar pata atras (pegada al suelo)
	#define	Levantarse	d'07'	; bajar la pata para levantar el cuerpo (broadcast)		
	#define	Descansar	d'08'	; Subir la pata hasta encojerla al cuerpo (broadcast)

	#define	Infrarrojos	PORTA,0	;RA0 - Sensor de infrarrojos
	#define	LimDist		d'32'	;Valor que define el límite de distancia a un obstáculo
					;para considerarlo demasiado cercano y reaccionar
					;para evitarlo. A mayor valor, el límite está a menos
					;centímetros del robot. Valor entre 0 y 255

;Definición de variables

	cblock	0x20		

	Posic		;Variable Posicion Servo para cálculo retardo
	Posic1		;Posicion Servo nº1 (0 a 235)
	Posic2		;Posicion Servo nº2 (0 a 235)
	Posic3		;Posicion Servo nº3 (0 a 235)
	PDel0		;Usada en retardos		
	ADel0		;Usada en retardos		
	BDel0		;Usada en retardos		
	BDel1		;Usada en retardos		
	BDel2		;Usada en retardos		
	Pausa		;Usada en para hacer pausas con subr "HacerTiempo"
	Temp		;Variable Temporal para usos puntuales en cálculos		
	Temp2		;Variable Temporal para usos puntuales en cálculos		
	Temp3		;Variable Temporal para usos puntuales en cálculos		
	MensajeIn	;Contendrá el dato recibido por I2C del slave
	MensajeOut	;Contendrá el dato a enviar por I2C al slave
	DirSlave	;Dirección del Slave	
	BkStatus	;Backup del registro STATUS 
	BkW		;Backup W
	BkStatus2	;Backup del registro STATUS (Interrupciones)
	BkW2		;Backup W (Interrupciones)
	Offset		;Valor Offset server (ver definición macros)
	Distancia	;Para medidas de distancia del sensor infrarrojo

	endc		;Fin de definiciones



	org	0
	goto	INICIO
	org	5		


;-------------------------------------------------------------------------------
Interrupcion   	;RUTINA DE INTERRUPCIÓN. Activa flancos segun valor de variables 
		;de Posicion (Servos)
;-------------------------------------------------------------------------------



	;Guardamos copia de algunos registros
	movwf	BkW2		;Hace copia de W
	movf	STATUS,W	;Hace copia de registro de estado
	banksel	PORTA
	movwf	BkStatus2


	;Es una interrupción de desbordamiento del TMR0 --> Gestión Servos

	bcf	INTCON,T0IF		;Repone flag del TMR0
	movlw 	d'182'      		;Repone el TMR0 con 177 (complemento de 78) -182
	banksel TMR0
        movwf 	TMR0			;256*78=19.968 (casi 20.000 usg= 20ms)

	movf	Posic1,W		;Carga variable Posic con valor posición para...
	movwf	Posic			;Servo nº1
	movlw	Offset1			;Carga Offset del server correspondiente
	movwf	Offset
	bsf     Servo1			; activamos flanco
	call	Retardo			;dejamos activo el tiempo necesario
	bcf     Servo1			; bajamos flanco

	movf	Posic2,W		;Carga variable Posic con valor posición para...
	movwf	Posic			;Servo nº2
	movlw	Offset2			;Carga Offset del server correspondiente
	movwf	Offset
	bsf     Servo2			; activamos flanco
	call	Retardo			;dejamos activo el tiempo necesario
	bcf     Servo2			; bajamos flanco

	movf	Posic3,W		;Carga variable Posic con valor posición para...
	movwf	Posic			;Servo nº3
	movlw	Offset3			;Carga Offset del server correspondiente
	movwf	Offset
	bsf     Servo3			; activamos flanco
	call	Retardo			;dejamos activo el tiempo necesario
	bcf     Servo3			; bajamos flanco


Rest	;Restauramos las copias de los registros
	movf	BkStatus2,W	;Restaura las copias de registros
	movwf	STATUS		;registro de estado
	movf	BkW2,W		;registro W

	retfie




; ---------------------------------------------------------------------------------------


INICIO		;Inicio del cuerpo del programa


	banksel	TRISB		;Apunta a banco 1
	movlw	b'00000000'	;Salida (Leds)
	movwf	TRISB		;

	;Configuración para uso de conversor A/D

	banksel	ADCON1		
	movlw	b'00000001'	;Establece puerta A como salida... 
	movwf	TRISA		;..excepto RA0 (Sensor)
	movlw	b'00001110'	;PORTA: RA0 entrada analog. Resto dig. Justif ADRESH (izda)
	movwf	ADCON1		;
	banksel ADCON0
	movlw	b'11000001'	;PORTA-RA0: osci interno, canal-0, activar conversion 
	movwf	ADCON0		;

	;Configuración para interrupciones por overflow de TMR0

	banksel OPTION_REG
	movlw	b'10000111'	;Configuracion OPTION para TMR0 (Prescaler 1:256)
	movwf	OPTION_REG
	movlw	b'10100000'	;Establece interrupciones
	movwf	INTCON		;activas para overflow de TMR0
	banksel	TMR0
	movlw 	d'182'      	;Activa el TMR0 con 177 (complemento de 78)
        movwf 	TMR0		;256*78=19.968 (casi 20.000 usg= 20ms)

	call	init_i2c_Master	;Configuración para uso de i2c

	banksel	MensajeIn
	clrf	MensajeIn
	clrf	MensajeOut
	clrf	Distancia	;Resetea medida sensor Infrarrojo
	clrf	PORTA

	movlw	d'90'			;Establece valor inicial de posicion servo
	movwf	Posic1		
	movlw	d'0'			;Establece valor inicial de posicion servo
	movwf	Posic2		
	movlw	d'0'			;Establece valor inicial de posicion servo
	movwf	Posic3		

	movlw	d'100'		;Pausa para que los slaves se estabilicen
	movwf	Pausa
	call	HacerTiempo

	movlw	Levantarse	;Levanta el cuerpo del suelo
	movwf	MensajeOut	;
	movlw	Broadcast	;Dirección de broadcast
	movwf	DirSlave	;
	call 	Enviar		;Manda la orden a todos los slaves


	;chequeo existencia obstáculo antes de hacer nada
	call	ChkObstacle	;Verifica la existencia de obstáculos
	xorlw	1
	btfsc	STATUS,Z	;Chequea si detectó obstáculo (1)
	Goto	Obstaculo	;Si. Se Se salta a la rutina adecuada
				;No se detectó obstáculo. Seguimos


BUCLE


	call	PasoAdelante	;Desplaza el cuerpo completo un paso hacia alante
	xorlw	1
	btfsc	STATUS,Z	;Chequea si detectó obstáculo (1)
	Goto	Obstaculo	;Si. Se Se salta a la rutina adecuada
				;No se detectó obstáculo. Seguimos

	goto	BUCLE


Obstaculo ;Procedemos a esquivar el obstáculo
	
	;Esta rutina no está completa, pero para verificar que la detección es correcta
	;Simplemente hacemos una pausa
	movlw	d'50'
	movwf	Pausa
	call	HacerTiempo
	goto	BUCLE



;*********************************************************************************
; SUBRUTINAS
;*********************************************************************************

; --------------------------------------------------------------------------------------
PasoAdelante	;Envía los mensajes necesarios a los Slaves para que Melanie de
		;un paso completo hacia delante. Si al dar el paso no detecta
		;obstáculo, devuelve 0 en W. Si hay obstáculo devuelve 1
;---------------------------------------------------------------------------------------

	;Posicionamos cabeza
	movlw	d'100'		;posicion servo (Cabeza)
	movwf	Posic1		
	movlw	d'20'
	movwf	Pausa
	call	HacerTiempo

	;chequeo existencia obstáculo
	call	ChkObstacle	;Verifica la existencia de obstáculos
	xorlw	1
	btfsc	STATUS,Z	;Chequea si detectó obstáculo (1)
	retlw	1		;Si. Se sale de subrutina con W=1 (Obstáculo detectado)
				;No se detectó obstáculo. Seguimos

	;Movemos pata
	movlw	D1		;Dirección del Slave con el que comunicarse
	movwf	DirSlave	;
	call	PisaAlante	;Mueve la pata alante y pisa suelo

	;Posicionamos cabeza
	movlw	d'80'		;posicion servo (Cabeza)
	movwf	Posic1		
	movlw	d'20'
	movwf	Pausa
	call	HacerTiempo

	;chequeo existencia obstáculo
	call	ChkObstacle	;Verifica la existencia de obstáculos
	xorlw	1
	btfsc	STATUS,Z	;Chequea si detectó obstáculo (1)
	retlw	1		;Si. Se sale de subrutina con W=1 (Obstáculo detectado)
				;No se detectó obstáculo. Seguimos

	;Movemos pata
	movlw	I1		;Dirección del Slave con el que comunicarse
	movwf	DirSlave	;
	call	PisaAlante	;Mueve la pata alante y pisa suelo

	;Posicionamos cabeza
	movlw	d'90'		;posicion servo (Cabeza)
	movwf	Posic1		

	;chequeo existencia obstáculo
	call	ChkObstacle	;Verifica la existencia de obstáculos
	xorlw	1
	btfsc	STATUS,Z	;Chequea si detectó obstáculo (1)
	retlw	1		;Si. Se sale de subrutina con W=1 (Obstáculo detectado)
				;No se detectó obstáculo. Seguimos

	;Movemos pata
	movlw	D2		;Dirección del Slave con el que comunicarse
	movwf	DirSlave	;
	call	PisaAlante	;Mueve la pata alante y pisa suelo

	;chequeo existencia obstáculo
	call	ChkObstacle	;Verifica la existencia de obstáculos
	xorlw	1
	btfsc	STATUS,Z	;Chequea si detectó obstáculo (1)
	retlw	1		;Si. Se sale de subrutina con W=1 (Obstáculo detectado)
				;No se detectó obstáculo. Seguimos
	;Movemos pata
	movlw	I2		;Dirección del Slave con el que comunicarse
	movwf	DirSlave	;
	call	PisaAlante	;Mueve la pata alante y pisa suelo

	;chequeo existencia obstáculo
	call	ChkObstacle	;Verifica la existencia de obstáculos
	xorlw	1
	btfsc	STATUS,Z	;Chequea si detectó obstáculo (1)
	retlw	1		;Si. Se sale de subrutina con W=1 (Obstáculo detectado)
				;No se detectó obstáculo. Seguimos
	;Movemos pata
	movlw	D3		;Dirección del Slave con el que comunicarse
	movwf	DirSlave	;
	call	PisaAlante	;Mueve la pata alante y pisa suelo

	;chequeo existencia obstáculo
	call	ChkObstacle	;Verifica la existencia de obstáculos
	xorlw	1
	btfsc	STATUS,Z	;Chequea si detectó obstáculo (1)
	retlw	1		;Si. Se sale de subrutina con W=1 (Obstáculo detectado)
				;No se detectó obstáculo. Seguimos
	;Movemos pata
	movlw	I3		;Dirección del Slave con el que comunicarse
	movwf	DirSlave	;
	call	PisaAlante	;Mueve la pata alante y pisa suelo

	;chequeo existencia obstáculo
	call	ChkObstacle	;Verifica la existencia de obstáculos
	xorlw	1
	btfsc	STATUS,Z	;Chequea si detectó obstáculo (1)
	retlw	1		;Si. Se sale de subrutina con W=1 (Obstáculo detectado)
				;No se detectó obstáculo. Seguimos

	;Desplazamos cuerpo
	movlw	Broadcast	;Dirección de broadcast
	movwf	DirSlave	;
	call	ArrastraAtras	;Arrastra la pata hacia atras (cuerpo se desplaza alante)

	;chequeo existencia obstáculo
	call	ChkObstacle	;Verifica la existencia de obstáculos
	xorlw	1
	btfsc	STATUS,Z	;Chequea si detectó obstáculo (1)
	retlw	1		;Si. Se sale de subrutina con W=1 (Obstáculo detectado)
				;No se detectó obstáculo. Seguimos

	Retlw	0		;Si llegamos aquí es que no se detectó obstáculo (W=0)


; --------------------------------------------------------------------------------------
PisaAtras	;Envía los mensajes necesarios al Slave cuya dirección se ha de encontrar
		;en la variable "DirSlave" para que ponga la pata atras en el suelo.
;---------------------------------------------------------------------------------------


	movlw	ArribaAtras
	movwf	MensajeOut
	call	Enviar

	movlw	d'40'
	movwf	Pausa
	call	HacerTiempo

	movlw	AbajoAtras		
	movwf	MensajeOut
	call	Enviar

	movlw	d'40'
	movwf	Pausa
	call	HacerTiempo

;	call	Recibir

	return


; --------------------------------------------------------------------------------------
ArrastraAlante	;Envía los mensajes necesarios al Slave cuya dirección se ha de encontrar
		;en la variable "DirSlave" para arrastre la pata alante en el suelo.
;---------------------------------------------------------------------------------------


	movlw	SueloAlante		
	movwf	MensajeOut
	call	Enviar

;	movlw	d'5'
;	movwf	Pausa
;	call	HacerTiempo
	RETURN

; --------------------------------------------------------------------------------------
PisaAlante	;Envía los mensajes necesarios al Slave cuya dirección se ha de encontrar
		;en la variable "DirSlave" para que ponga la pata alante en el suelo.
;---------------------------------------------------------------------------------------


	movlw	ArribaAlante
	movwf	MensajeOut
	call	Enviar

	movlw	d'10'
	movwf	Pausa
	call	HacerTiempo

	movlw	AbajoAlante		
	movwf	MensajeOut
	call	Enviar

	movlw	d'30'
	movwf	Pausa
	call	HacerTiempo

	call	Recibir


	return


; --------------------------------------------------------------------------------------
ArrastraAtras	;Envía los mensajes necesarios al Slave cuya dirección se ha de encontrar
		;en la variable "DirSlave" para arrastre la pata atras en el suelo.
;---------------------------------------------------------------------------------------


	movlw	SueloAtras		
	movwf	MensajeOut
	call	Enviar

	movlw	d'35'
	movwf	Pausa
	call	HacerTiempo
	RETURN



;---------------------------------------------------------------------------------------
HacerTiempo	;realiza una pausa del numero de centesimas de segundo especificadas en "Pausa"
		
;---------------------------------------------------------------------------------------

	movf	Pausa,W		;Coloca el valor de pausa en BDel2...
	movwf	BDel2		;...para no alterar su contenido
	
;............................................................
; Generado con PDEL ver SP  r 1.0  el 24/02/03 Hs 18:31:22
; Descripcion: Delay 10000 ciclos (1 centésima de segundo)
;............................................................
BCiclo  movlw     .8        ; 1 set numero de repeticion  (B)
        movwf     BDel0     ; 1 |
BLoop1  movlw     .249      ; 1 set numero de repeticion  (A)
        movwf     BDel1     ; 1 |
BLoop2  nop                 ; 1 nop   
        nop                 ; 1 ciclo delay
        decfsz    BDel1, 1  ; 1 + (1) es el tiempo 0  ? (A)
        goto      BLoop2    ; 2 no, loop
        decfsz    BDel0,  1 ; 1 + (1) es el tiempo 0  ? (B)
        goto      BLoop1    ; 2 no, loop
BDelL1  goto BDelL2         ; 2 ciclos delay
BDelL2  nop                 ; 1 ciclo delay
;............................................................
	decfsz	BDel2,F		;Repite tantas veces el ciclo de una decima de segundo...
	goto	BCiclo		;..como se lo indique ADel2
        return              ; 2+2 Fin.


; ---------------------------------------------------------------------------------------
Retardo		;Provoca un retardo segun el valor de "Posic" y "Offset"
; ---------------------------------------------------------------------------------------

;Chequeo inicial: Delay fijo de 4usg (4 ciclos)
;-------------


	movf	Posic,F		;Checkeamos si el valor es cero
	btfsc	STATUS,Z	;
	goto	DelFijo		;Si es cero salta a la parte de delay fijo
	NOP


;Primera parte: Delay variable en función Posic (entre 0 y 180. 11 ciclos/grado)
;--------------

PLoop0  NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	decfsz  Posic,F  	; 1 + (1) es el tiempo 0  ?
        goto    PLoop0    	; 2 no, loop
	NOP


;Segunda parte: Delay fijo dependiente del valor de Offset. Ciclos=10+5xOffset (ver definición macros)
;-------------

DelFijo	NOP
	movf	Offset,W     	; 1 set numero de repeticion 
        movwf	PDel0     	; 1 |
SLoop0  NOP
	NOP
        decfsz	PDel0, 1  	; 1 + (1) es el tiempo 0  ?
        goto	SLoop0    	; 2 no, loop
        return              	; 2+2 Fin.



; ---------------------------------------------------------------------------------------
ChkObstacle	;Mide distancia hasta un objeto (detección de obstáculos). Si no detecta
		;obstáculo, devuelve 0 en W. Si hay obstáculo devuelve 1
; ---------------------------------------------------------------------------------------

	banksel	ADCON0
	bsf	ADCON0,GO	;Hace medición de distancia
AD_W	btfss	PIR1,ADIF	;Conversión finalizada?	
	goto	AD_W		;No
	movf	ADRESH,W	;Si --> Pasa valor a variable "Distancia"
	movwf	Distancia

	movwf	PORTB		;Muestra distancia por PORTB

	;Comparación con límite de distancia definido por la constante "LimDist"
	movlw	LimDist		;Valor de límite de distancia
	subwf	Distancia,W	;Resta/compara con dato "Distancia"
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	Retlw	1		;Si. (Distancia límite. Hay obstáculo)
	btfsc	STATUS,C	;No. Mayor (C=0)??
	Retlw	1		;Si. (Obstáculo. Superada distancia límite)
	Retlw	0		;No, No hay obstáculo

		


;-------------------------------------------------------------------------------
init_i2c_Master		;Inicializa valores para uso de I2C en Master
			;Ha de ser llamado tras definir TRISC y un valor para
			;ClockValue. Para frecuencia SCL=Fosc/(4x(ClockValue+1))
;-------------------------------------------------------------------------------

	;Guardamos copia de algunos registros
	movwf	BkW		;Hace copia de W
	movf	STATUS,W	;Hace copia de registro de estado
	banksel	PORTA
	movwf	BkStatus

	;Configuramos I2C
	banksel TRISC		; Pasamos a direccionar Banco 1
	movlw 	b'00011000'	; Establece líneas SDA y SCL como entradas...
	iorwf 	TRISC,f		;..respetando los valores para otras líneas.
	movlw 	ClockValue 	; Establece velocidad I2C segun...
	movwf 	SSPADD 		; ...valor de ClockValue 	
	bcf 	SSPSTAT,6 	; Establece I2C input levels
	bcf 	SSPSTAT,7 	; Habilita slew rate
	banksel SSPCON 		; Pasamos a direccionar Banco 0
	movlw 	b'00111000'	; Master mode, SSP enable, velocidad segun...
	movwf 	SSPCON 		; ... Fosc/(4x(SSPADD+1))
	bcf	PIR1,SSPIF	; Limpia flag de eventos SSP
	bcf	PIR1,7		; Limpia bit. Mandatorio por Datasheet

	;Restauramos las copias de los registros
	movf	BkStatus,W	;Restaura las copias de registros
	movwf	STATUS		;registro de estado
	movf	BkW,W		;registro W

	return


; --------------------------------------------------------------------------------------
Enviar	;Envía un mensaje (comando) almacenado en "MensajeOut" al Slave cuya dirección
	;se ha de encontrarse en la variable "DirSlave"
;---------------------------------------------------------------------------------------


	;Guardamos copia de algunos registros
	movwf	BkW		;Hace copia de W
	movf	STATUS,W	;Hace copia de registro de estado
	banksel	PORTA
	movwf	BkStatus

StEnv	call	Send_Start	;Envía condición de inicio
	call	CheckIdle	;Espera fin evento
	banksel	DirSlave
	movf	DirSlave,W	;Dirección esclavo
	call	Send_Byte	;Envía dirección y orden de escritura
	call	CheckIdle	;Espera fin evento
	call	WrtAckTest	;Verifica llegada ACK
	banksel SSPCON2 	
	bcf	SSPCON2,ACKSTAT	;limpia flag ACK
	xorlw	1
	btfsc	STATUS,Z	;Chequea si llegó ACK
	goto	StEnv		;No. Reintentamos envío
	banksel MensajeOut	;Si. Seguimos con envío dato
	movf	MensajeOut,W	;Lo deja en W para que la subrutina Send_Byte lo envíe

	call	Send_Byte	;envía por i2c
	call	CheckIdle	;Espera fin evento
	call	Send_Stop	;Envia condición de parada
	call	CheckIdle	;Espera fin evento

	;Restauramos las copias de los registros
	movf	BkStatus,W	;Restaura las copias de registros
	movwf	STATUS		;registro de estado
	movf	BkW,W		;registro W

	return


; --------------------------------------------------------------------------------------
Recibir	;Solicita dato al Slave cuya dirección ha de encontrarse en la variable 
	;"DirSlave" y lo mete en "MensajeIn".
;---------------------------------------------------------------------------------------

	;Guardamos copia de algunos registros
	movwf	BkW		;Hace copia de W
	movf	STATUS,W	;Hace copia de registro de estado
	banksel	PORTA
	movwf	BkStatus

StRec	call	CheckIdle	;Espera fin evento
	call	Send_Stop	;Envía condición de stop (para reiniciar slave)
	call	CheckIdle	;Espera fin evento
	call	Send_Start	;Envía condición de inicio
	call	CheckIdle	;Espera fin evento
	banksel	DirSlave
	movf	DirSlave,W	;Dirección esclavo
	iorlw	b'00000001'	;con orden de lectura
	call	Send_Byte	;Envía dirección y orden de lectura
	call	CheckIdle	;Espera fin evento
	call	WrtAckTest	;Verifica llegada ACK
	banksel SSPCON2 	
	bcf	SSPCON2,ACKSTAT	;limpia flag ACK
	xorlw	1
	btfsc	STATUS,Z	;Chequea si llegó ACK
	goto	StRec		;No. Reintentamos envío
				;Si. Leemos dato
	call	Rec_Byte	;Recibe dato por i2c y lo mete en "MensajeIn"
	call	CheckIdle	;Espera fin evento
	call	Send_Nack	;Envía Nack para finalizar recepción
	call	CheckIdle	;Espera fin evento
	call	Send_Stop	;Envía condición de stop
	call	CheckIdle	;Espera fin evento

	;Restauramos las copias de los registros
	movf	BkStatus,W	;Restaura las copias de registros
	movwf	STATUS		;registro de estado
	movf	BkW,W		;registro W

	return



; --------------------------------------------------------------------------------------
Send_Start	;Envía condición de start
;---------------------------------------------------------------------------------------

	banksel SSPCON2 		
	bsf 	SSPCON2,SEN 	; Envía Start
	return 


; --------------------------------------------------------------------------------------
Send_Ack	;Envía Ack
;---------------------------------------------------------------------------------------

	banksel SSPCON2 	
	bcf 	SSPCON2,ACKDT 	; acknowledge bit state to send (ack)
	bsf 	SSPCON2,ACKEN 	; Inicia secuencia de ack
	return


; --------------------------------------------------------------------------------------
Send_Nack	;Envía Nack para finalizar recepción
;---------------------------------------------------------------------------------------

	banksel SSPCON2 	
	bsf 	SSPCON2,ACKDT 	; acknowledge bit state to send (not ack)
	bsf 	SSPCON2,ACKEN 	; Inicia secuencia de nack
	return


; --------------------------------------------------------------------------------------
Send_Stop	;Envía condición de stop
;---------------------------------------------------------------------------------------

	banksel SSPCON2	
	bsf	SSPCON2,PEN	;Activa secuencia de stop
	return				


; --------------------------------------------------------------------------------------
Send_Byte	;Envía el contenido de W por i2c
;---------------------------------------------------------------------------------------

	banksel SSPBUF 		; Cambia a banco 0
	movwf 	SSPBUF 		; inicia condicion de escritura
	return	



; --------------------------------------------------------------------------------------
Rec_Byte	;Recibe dato por i2c y lo mete en "MensajeIn"
;---------------------------------------------------------------------------------------

	banksel SSPCON2 	; Cambia a banco 1
	bsf 	SSPCON2,RCEN 	; genera receive condition
	btfsc 	SSPCON2,RCEN	; espera a que llegue el dato
	goto 	$-1
	banksel SSPBUF		; Cambia a banco 0
	movf 	SSPBUF,w 	; Mueve el dato recibido ...
	movwf 	MensajeIn 	; ...  a MensajeIn
	return


; --------------------------------------------------------------------------------------
CheckIdle	;Chequea que la operación anterior termino y se puede proceder con
		;el siguiente evento SSP
;---------------------------------------------------------------------------------------

	banksel SSPSTAT		; Cambia a banco 1
	btfsc 	SSPSTAT, R_W 	; Transmisión en progreso?
	goto 	$-1
	movf 	SSPCON2,W 		
	andlw 	0x1F 		; Chequeamos con mascara para ver si evento en progreso
	btfss 	STATUS, Z
	goto 	$-3 		; Sigue en progreso o bus ocupado. esperamos
	banksel PIR1		; Cambia a banco 0
	bcf 	PIR1,SSPIF	; Limpiamos flag
	return


;---------------------------------------------------------------------------------------
WrtAckTest	;Chequea ack tras envío de dirección o dato
		;Devuelve en W 0 o 1 dependiendo de si llegó (0) o no (1) ACK
;---------------------------------------------------------------------------------------

	banksel SSPCON2 	; Cambia a banco 1	
	btfss 	SSPCON2,ACKSTAT ;Chequea llegada ACK desde slave
	retlw	0		;llegó ACK
	retlw	1		;no llegó ACK


Fin
	END
