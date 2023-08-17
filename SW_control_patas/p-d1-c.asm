; p-d1-c
; Programa para control de Pata derecha n�1 de Melanie. servos y entrada anal�gica (Sensor presi�n)
; Por: Alejandro Alonso Puig
; Fecha: 17/4/2003
; Controlador: 16F876
; Funci�n: 
; Servos utilizados:  Articulaciones 1 y 3: Robbe FS100; Artic 2: Robbe FS250T
; Control mediante I2C desde comandos del Master. Estos comandos se dejan en la
; Variable "MensajeIn". Este programa permite actuar como slave. Tanto mensajes
; de error como de �xito ser�n mandados al Master mediante I2C con la variable "MensajeOut"
; El valor de posicionamiento se entrega a una subrutina en grados (0� a 180�)
; Adicionalmente hay una entrada anal�gica. El valor de dicha entrada se muestra 
; en barrera de leds a modo vuumetro. La llamada a la rutina de medida est�
; en la propia rutina de interrupci�n para asegurar que siempre se tiene
; un valor en tiempo real de "Presion"



	list 		p=16F876
	include		"P16F876.INC"


;Definici�n de macros

	#define	DirNodo		b'01110000'	;Direcci�n I2C de este nodo

	;Definiciones servos
	#define	Servo1	PORTA,1	;RA1 - Servo n�1
	#define	Servo2	PORTA,2	;RA2 - Servo n�2
	#define	Servo3	PORTA,3	;RA3 - Servo n�3
	#define	Offset1	d'60'	;Offset Servo n�1
	#define	Offset2	d'150'	;Offset Servo n�2
	#define	Offset3	d'66'	;Offset Servo n�3
	;El valor de Offset permite establecer la posici�n de cero grados en funci�n 
	;de la anchura del pulso activo en microsegundos. El c�lculo se hace mediante 
	;la f�rmula Offset=(T-10)/5, donde T es la anchura del pulso activo en usg
	;Se utiliza para dos funciones: Ajustar varios servos para que sus ejes est�n
	;colocados f�sicamente en la misma posici�n para cero grados, adaptando los
	;offsets de cada servo. Tambi�n se utiliza para aprovechar al m�ximo el giro
	;posible del eje, que varia para cada marca y modelo.
	;Por ejemplo, si queremos establecer que el valor de 0� implique un pulso
	;activo de una anchura de 1000usg, el offset ser� (1000-10)/5=198

	;Mensajes para enviar al master
	#define	NoError		d'0'	;No error
	#define	ErrSuelo	d'1'	;Error de suelo
	#define	ErrMensaje	d'2'	;Mensaje recibido desconocido

	;Mensajes a recibir del Master
	#define	NoHacerNada	d'00'	; No hacer nada
	#define	ArribaAlante	d'01'	; Subir pata adelante
	#define	ArribaAtras	d'02'	; Subir pata atras
	#define	AbajoAlante	d'03'	; Bajar pata
	#define	AbajoAtras	d'04'	; Bajar pata
	#define	SueloAlante	d'05'	; Desplazar pata adelante (pegada al suelo)
	#define	SueloAtras	d'06'	; Desplazar pata atras (pegada al suelo)
	#define	Levantarse	d'07'	; bajar la pata para levantar el cuerpo (broadcast)		
	#define	Descansar	d'08'	; Subir la pata hasta encojerla al cuerpo (broadcast)

	#define	Sensor		PORTA,0	;RA0 - Sensor de presi�n anal�gico

;Definici�n de variables

	cblock	0x20	

	Posic		;Variable Posicion Servo para c�lculo retardo
	Posic1		;Posicion Servo n�1 (0 a 235)
	Posic2		;Posicion Servo n�2 (0 a 235)
	Posic3		;Posicion Servo n�3 (0 a 235)
	PDel0		;Usada en retardos		
	ADel0		;Usada en retardos		
	BDel0		;Usada en retardos		
	BDel1		;Usada en retardos		
	BDel2		;Usada en retardos		
	Presion		;Valor del sensor de presion. Para llamada a Subrutina "DisplayPresion"
	Pausa		;Usada en para hacer pausas con subr "HacerTiempo"
	Temp		;Variable Temporal usada para evaluaci�n de eventos I2C
	Temp2		;Variable usada en procesos puntuales		
	Temp3		;Variable usada en procesos puntuales		
	MensajeIn	;Contendr� el dato recibido por I2C del master
	MensajeOut	;Contendr� el dato a enviar por I2C al master
	BkStatus	;Backup del registro STATUS (Usado en interrupciones)
	BkW		;Backup W
	Offset		;Valor Offset server (ver definici�n macros)

	endc			;Fin de definiciones

	; Definiciones bits del registro RA

	;Atenci�n, RA4 en modo salida trabaja en colector abierto


	org	0
	goto	INICIO
	org	5		


;-------------------------------------------------------------------------------
Interrupcion   	;RUTINA DE INTERRUPCI�N. Activa flancos segun valor de variables 
		;de Posicion y se ocupa de los eventos I2C
;-------------------------------------------------------------------------------



	;Guardamos copia de algunos registros
	movwf	BkW		;Hace copia de W
	movf	STATUS,W	;Hace copia de registro de estado
	banksel	PORTA
	movwf	BkStatus

	;Chequeamos si la interrupci�n es por evento I2C. En caso positivo llamamos
	;a la rutina de proceso del evento
	banksel PIR1
	btfss	PIR1,SSPIF	;Ha ocurrido un evento SSP? (I2C)
	goto	IntNoSSP	;No. entonces ser� por otra cosa. Saltamos.
	call	SSP_Handler	;Si. Procesamos el evento. Si se reciben ordenes, quedar�n
				;registradas en "MensajeIn". Se enviar�n las ordenes 
				;guardadas en "MensajeOut".
	banksel PIR1
	bcf	PIR1,SSPIF	;Limpiamos el flag
	goto	Rest


IntNoSSP	;Aqu� se gestionan interrupciones que no son por SSP


	;Es una interrupci�n de desbordamiento del TMR0 --> Gesti�n Servos

	bcf	INTCON,T0IF		;Repone flag del TMR0
	movlw 	d'182'      		;Repone el TMR0 con 177 (complemento de 78) -182
	banksel TMR0
        movwf 	TMR0			;256*78=19.968 (casi 20.000 usg= 20ms)

	movf	Posic1,W		;Carga variable Posic con valor posici�n para...
	movwf	Posic			;Servo n�1
	movlw	Offset1			;Carga Offset del server correspondiente
	movwf	Offset
	bsf     Servo1			; activamos flanco
	call	Retardo			;dejamos activo el tiempo necesario
	bcf     Servo1			; bajamos flanco

	movf	Posic2,W		;Carga variable Posic con valor posici�n para...
	movwf	Posic			;Servo n�2
	movlw	Offset2			;Carga Offset del server correspondiente
	movwf	Offset
	bsf     Servo2			; activamos flanco
	call	Retardo			;dejamos activo el tiempo necesario
	bcf     Servo2			; bajamos flanco

	movf	Posic3,W		;Carga variable Posic con valor posici�n para...
	movwf	Posic			;Servo n�3
	movlw	Offset3			;Carga Offset del server correspondiente
	movwf	Offset
	bsf     Servo3			; activamos flanco
	call	Retardo			;dejamos activo el tiempo necesario
	bcf     Servo3			; bajamos flanco

	Call	MidePresion	;Mide presi�n, la almacena en "Presion" y muestra en barrera de leds

	bsf 	SSPCON,CKP	;Activamos reloj I2C (Por si se detuvo en procedimiento "Retardo")

Rest	;Restauramos las copias de los registros
	movf	BkStatus,W	;Restaura las copias de registros
	movwf	STATUS		;registro de estado
	movf	BkW,W		;registro W

	retfie


;-------------------------------------------------------------------------------


INICIO		;Inicio del cuerpo del programa

	banksel	TRISB		;Apunta a banco 1
	movlw	b'00000000'	;Salida (Leds)
	movwf	TRISB		;

	;Configuraci�n para uso de conversor A/D

	banksel	ADCON1		
	movlw	b'00000110'	;PORTA: RA0 entrada analog. Resto dig. Justif ADRESH(izda) 
	movwf	ADCON1		;
	movlw	b'00000001'	;Establece puerta A como salida... 
	movwf	TRISA		;..excepto RA0 (Sensor)
	movlw	b'00001110'	;PORTA: RA0 entrada analog. Resto dig. Justif ADRESH 
	movwf	ADCON1		;
	banksel ADCON0
	movlw	b'11000001'	;PORTA-RA0: osci interno, canal-0, activar conversion 
	movwf	ADCON0		;
	
	;Configuraci�n para interrupciones por overflow de TMR0

	banksel OPTION_REG
	movlw	b'10000111'	;Configuracion OPTION para TMR0 (Prescaler 1:256)
	movwf	OPTION_REG
	movlw	b'10100000'	;Establece interrupciones
	movwf	INTCON		;activas para overflow de TMR0
	banksel	TMR0
	movlw 	d'182'      	;Activa el TMR0 con 177 (complemento de 78)
        movwf 	TMR0		;256*78=19.968 (casi 20.000 usg= 20ms)

	call	init_i2c_Slave	;Configuraci�n para uso de i2c

	banksel	PORTA
	clrf	PORTA
	clrf	PORTB
	clrf	MensajeOut	;Establece mensaje de NoError
	clrf	MensajeIn	;Establece como acci�n NoHacerNada hasta que se reciba nueva orden
	clrf	Presion



	call 	Encojerse	;Pega la pata al cuerpo




BUCLE	;Bucle principal del programa

;	call 	ArribaBody	;Levanta el cuerpo

;	call 	SubeAlFrente	;Sube la pata y la coloca delante (primera fase de un paso adelante)
;	call 	BajadaAlante	;Baja la pata quedando adelante (Segunda fase de un paso adelante)
;	call 	DesplazaAtras	;Desplaza la pata hacia atr�s (Tercera fase de un paso adelante)

;	call 	SubeAtras	;Sube la pata y la coloca atras (primera fase de un paso atras)
;	call 	BajadaAtras	;Baja la pata quedando adelante (Segunda fase de un paso adelante)
;	call 	DesplazaAlante	;Desplaza la pata hacia alante (Tercera fase de un paso atras)


	;Procedemos a actuar seg�n la orden recibida del Master. Haremos un Pseudo CASE

M_00	;NoHacerNada (No ha llegado nueva orden del Master)
	movlw 	NoHacerNada	;
	xorwf 	MensajeIn,W	;
	btfss 	STATUS,Z 	; Es este el comando recibido?
	goto 	M_01 		; No, chequeamos siguiente comando
	goto	BUCLE	 	; Si. Pues hacemos lo pedido: Nada. Regresar al bucle

M_01	;ArribaAlante (Subir pata adelante)
	movlw 	ArribaAlante	;
	xorwf 	MensajeIn,W	;
	btfss 	STATUS,Z 	; Es este el comando recibido?
	goto 	M_02 		; No, chequeamos siguiente comando
	clrf	MensajeIn 	; Si. Limpiamos Mensaje y procedemos a ejecutar la acci�n
	call 	SubeAlFrente	;Sube la pata y la coloca delante (primera fase de un paso adelante)
	clrf	MensajeOut	;No hubo error
	goto	BUCLE		;Regresamos a la espera de una nueva orden del Master

M_02	;ArribaAtras (Subir pata atras)
	movlw 	ArribaAtras	;
	xorwf 	MensajeIn,W	;
	btfss 	STATUS,Z 	; Es este el comando recibido?
	goto 	M_03 		; No, chequeamos siguiente comando
	clrf	MensajeIn 	; Si. Limpiamos Mensaje y procedemos a ejecutar la acci�n
	call 	SubeAtras	;Sube la pata y la coloca atras (primera fase de un paso atras)
	clrf	MensajeOut	;No hubo error
	goto	BUCLE		;Regresamos a la espera de una nueva orden del Master

M_03	;AbajoAlante (Bajar pata alante)
	movlw 	AbajoAlante	;
	xorwf 	MensajeIn,W	;
	btfss 	STATUS,Z 	; Es este el comando recibido?
	goto 	M_04 		; No, chequeamos siguiente comando
	clrf	MensajeIn 	; Si. Limpiamos Mensaje y procedemos a ejecutar la acci�n
	call 	BajadaAlante	;Baja la pata quedando adelante (Segunda fase de un paso adelante)
	clrf	MensajeOut	;No hubo error
	goto	BUCLE		;Regresamos a la espera de una nueva orden del Master

M_04	;AbajoAtras (Bajar pata atras)
	movlw 	AbajoAtras	;
	xorwf 	MensajeIn,W	;
	btfss 	STATUS,Z 	; Es este el comando recibido?
	goto 	M_05 		; No, chequeamos siguiente comando
	clrf	MensajeIn 	; Si. Limpiamos Mensaje y procedemos a ejecutar la acci�n
	call 	BajadaAtras	;Baja la pata quedando adelante (Segunda fase de un paso atras)
	clrf	MensajeOut	;No hubo error
	goto	BUCLE		;Regresamos a la espera de una nueva orden del Master

M_05	;SueloAlante (Desplaza la pata hacia alante (Tercera fase de un paso atras))
	movlw 	SueloAlante	;
	xorwf 	MensajeIn,W	;
	btfss 	STATUS,Z 	; Es este el comando recibido?
	goto 	M_06 		; No, chequeamos siguiente comando
	clrf	MensajeIn 	; Si. Limpiamos Mensaje y procedemos a ejecutar la acci�n
	call 	DesplazaAlante	;Desplaza la pata hacia alante (Tercera fase de un paso atras)
	clrf	MensajeOut	;No hubo error
	goto	BUCLE		;Regresamos a la espera de una nueva orden del Master


M_06	;SueloAtras (Desplazar pata atras (pegada al suelo))
	movlw 	SueloAtras	;
	xorwf 	MensajeIn,W	;
	btfss 	STATUS,Z 	; Es este el comando recibido?
	goto 	M_07 		; No, chequeamos siguiente comando
	clrf	MensajeIn 	; Si. Limpiamos Mensaje y procedemos a ejecutar la acci�n
	call 	DesplazaAtras	;Desplaza la pata hacia atr�s (Tercera fase de un paso adelante)
	clrf	MensajeOut	;No hubo error
	goto	BUCLE		;Regresamos a la espera de una nueva orden del Master

M_07	;Levantarse (bajar la pata para levantar el cuerpo)
	movlw 	Levantarse	;
	xorwf 	MensajeIn,W	;
	btfss 	STATUS,Z 	; Es este el comando recibido?
	goto 	M_08 		; No, chequeamos siguiente comando
	clrf	MensajeIn 	; Si. Limpiamos Mensaje y procedemos a ejecutar la acci�n
	call 	ArribaBody	;Levanta el cuerpo
	clrf	MensajeOut	;No hubo error
	goto	BUCLE		;Regresamos a la espera de una nueva orden del Master

M_08	;Descansar (Subir la pata hasta encojerla al cuerpo (broadcast))
	movlw 	Descansar	;
	xorwf 	MensajeIn,W	;
	btfss 	STATUS,Z 	; Es este el comando recibido?
	goto 	M_Error 	; No, chequeamos siguiente comando
	clrf	MensajeIn 	; Si. Limpiamos Mensaje y procedemos a ejecutar la acci�n
	call 	Encojerse	;Pega la pata al cuerpo
	clrf	MensajeOut	;No hubo error
	goto	BUCLE		;Regresamos a la espera de una nueva orden del Master

M_Error	;No es un mensaje conocido, por lo que devolvemos mensaje de error y no hacemos nada
	Movlw	ErrMensaje	
	movwf	MensajeOut

	goto	BUCLE





;*********************************************************************************
; SUBRUTINAS
;*********************************************************************************

; ---------------------------------------------------------------------------------------
Encojerse	;Encoje la pata para que quede pegada al cuerpo
; ---------------------------------------------------------------------------------------

	movlw	d'90'			;Establece valor inicial de posicion
	movwf	Posic1		
	movlw	d'12'			;Establece valor inicial de posicion
	movwf	Posic2		
	movlw	d'176'			;Establece valor inicial de posicion
	movwf	Posic3		
	return


; ---------------------------------------------------------------------------------------
SubeAlFrente	;Sube la pata y la coloca delante (primera fase de un paso adelante)
; ---------------------------------------------------------------------------------------

	;subida y desplazamiento


	movlw	d'10'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'005'
	movwf	Pausa
	call	HacerTiempo 	;pausa
	movlw	d'48'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'150'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'020'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	return



; ---------------------------------------------------------------------------------------
BajadaAlante		;Baja la pata (Segunda fase de un paso adelante)
; ---------------------------------------------------------------------------------------


	movlw	d'48'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'41'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'126'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'010'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	Return


; ---------------------------------------------------------------------------------------
DesplazaAtras	;Desplaza la pata hacia atr�s (Tercera fase de un paso adelante)
; ---------------------------------------------------------------------------------------

	movlw	d'48'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'41'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'126'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'002'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'50'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'41'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'128'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'002'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'55'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'41'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'132'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'003'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'62'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'41'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'138'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'003'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'68'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'40'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'142'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'003'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'76'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'40'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'145'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'003'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'82'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'40'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'148'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'003'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'88'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'40'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'150'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'003'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'94'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'40'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'152'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'003'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'98'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'40'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'154'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'003'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	return


; ---------------------------------------------------------------------------------------
SubeAtras	;Sube la pata y la coloca atras (primera fase de un paso atras)
; ---------------------------------------------------------------------------------------

	;subida y desplazamiento

	movlw	d'10'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'005'
	movwf	Pausa
	call	HacerTiempo 	;pausa
	movlw	d'98'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'170'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'020'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	return


; ---------------------------------------------------------------------------------------
BajadaAtras		;Baja la pata (Segunda fase de un paso atras)
; ---------------------------------------------------------------------------------------


	movlw	d'98'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'40'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'154'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'010'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	Return


; ---------------------------------------------------------------------------------------
DesplazaAlante	;Desplaza la pata hacia alante (Tercera fase de un paso atras)
; ---------------------------------------------------------------------------------------


	movlw	d'98'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'40'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'154'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'003'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'94'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'40'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'152'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'003'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'88'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'40'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'150'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'003'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'82'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'40'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'148'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'003'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'76'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'40'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'145'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'003'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'68'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'40'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'142'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'003'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'62'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'41'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'138'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'003'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'55'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'41'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'132'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'002'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'50'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'41'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'128'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'002'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	movlw	d'48'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'41'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'126'
	movwf	Posic3		;mueve articulaci�n 3
	movlw	d'003'
	movwf	Pausa
	call	HacerTiempo 	;pausa

	return



; ---------------------------------------------------------------------------------------
ArribaBody		;Baja la pata en una forma especial para levantar el cuerpo
; ---------------------------------------------------------------------------------------

	;Primero coloca la pata arriba

	movlw	d'10'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'005'
	movwf	Pausa
	call	HacerTiempo 	;pausa
	movlw	d'48'
	movwf	Posic1		;mueve articulaci�n 1
	movlw	d'132'
	movwf	Posic3		;mueve articulaci�n 3

	;y luego la baja despacio

	movlw	d'5'		; Articulaci�n 2 ha de moverse 30 grados (6*5=30)
	movwf	Temp3		;
	movlw	d'004'
	movwf	Pausa

Cic1	decf	Posic3,F	;Se acerca 1 grado m�s a su destino
	movlw	d'6'		; Articulaci�n 3 ha de moverse 1 grado por cada 6 de...
	movwf	Temp2		; ... Articulaci�n 2.
Cic2	incf	Posic2,F	;Se acerca 1 grado m�s a su destino
	call	HacerTiempo 	;pausa
	decfsz  Temp2, F  	; es Temp2 0  ?
        goto    Cic2    	; no
	decfsz  Temp3, F  	; Si, es Temp3 0  ?
	goto	Cic1		;no
				;si. ya est� posicionado

	movlw	d'41'
	movwf	Posic2		;mueve articulaci�n 2
	movlw	d'126'
	movwf	Posic3		;mueve articulaci�n 3

	Return


;---------------------------------------------------------------------------------------
HacerTiempo	;realiza una pausa del numero de centesimas de segundo especificadas en "Pausa"
		;Este tiempo es aproximado ya que hay interrupciones del TMR0 para los servos
;---------------------------------------------------------------------------------------

	movf	Pausa,W		;Coloca el valor de pausa en BDel2...
	movwf	BDel2		;...para no alterar su contenido
	
;............................................................
; Generado con PDEL ver SP  r 1.0  el 24/02/03 Hs 18:31:22
; Descripcion: Delay 10000 ciclos (1 cent�sima de segundo)
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
MidePresion	;Mide presi�n en el sensor de la pata y almacena el valor de voltios en "Presion"
		; Luego muestra presi�n en barrera de leds seg�n el valor de la variable "Presion"
		;Esto se realiza mediante sucesivas comparaciones entre los 8 bits de mas peso
		;devueltos por el C A/D (Presion) y valores (8 bits de mas peso) correspondientes
		;a diferentes voltajes en el rango 2.50 a 4.00v)
; ---------------------------------------------------------------------------------------

	banksel	ADCON0
	bsf	ADCON0,GO	;Hace medici�n de presi�n
AD_W	btfss	PIR1,ADIF	;Conversi�n finalizada?	
	goto	AD_W
	movf	ADRESH,W
	movwf	Presion

	btfsc	PIR1,SSPIF	; Ha ocurrido un evento SSP? (I2C)
	bcf 	SSPCON,CKP	; Si. Detenemos reloj I2C para evitar desbordamiento o timeout

	;Comparaci�n con >=4 voltios. Aprox: 818=(4*1023/5). 8bits mayores: 11001100
	movlw	b'11001100'	;Valor en C A/D equivalente al voltaje a comparar
	subwf	Presion,W	;Resta/compara con dato "Presion" (Que en realidad es un valor de voltaje)
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	goto	NoPres		;Si. (Voltaje comparado. No hay presion)
	btfsc	STATUS,C	;No. Mayor (C=0)??
	goto	NoPres		;Si. (Mayor que voltaje comparado. No hay presion)
				;No, Voltaje menor

	;Comparaci�n con 3.75 voltios. Aprox: 767=(3.75*1023/5). 8bits mayores: 10111111
	movlw	b'10111111'	;Valor en C A/D equivalente al voltaje a comparar
	subwf	Presion,W	;Resta/compara con dato "Presion" (Que en realidad es un valor de voltaje)
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	goto	P0		;Si. (Voltaje comparado.)
	btfsc	STATUS,C	;No. Mayor (C=0)??
	goto	P0		;Si. (Mayor que voltaje comparado pero menor que voltaje anterior)
				;No, Voltaje menor

	;Comparaci�n con 3.50 voltios. Aprox: 716=(3.50*1023/5). 8bits mayores: 10110011
	movlw	b'10110011'	;Valor en C A/D equivalente al voltaje a comparar
	subwf	Presion,W	;Resta/compara con dato "Presion" (Que en realidad es un valor de voltaje)
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	goto	P1		;Si. (Voltaje comparado.)
	btfsc	STATUS,C	;No. Mayor (C=0)??
	goto	P1		;Si. (Mayor que voltaje comparado pero menor que voltaje anterior)
				;No, Voltaje menor

	;Comparaci�n con 3.25 voltios. Aprox: 665=(3.25*1023/5). 8bits mayores: 10100110
	movlw	b'10100110'	;Valor en C A/D equivalente al voltaje a comparar
	subwf	Presion,W	;Resta/compara con dato "Presion" (Que en realidad es un valor de voltaje)
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	goto	P2		;Si. (Voltaje comparado.)
	btfsc	STATUS,C	;No. Mayor (C=0)??
	goto	P2		;Si. (Mayor que voltaje comparado pero menor que voltaje anterior)
				;No, Voltaje menor
	;Comparaci�n con 3 voltios. Aprox: 614=(3*1023/5). 8bits mayores: 10011001
	movlw	b'10011001'	;Valor en C A/D equivalente al voltaje a comparar
	subwf	Presion,W	;Resta/compara con dato "Presion" (Que en realidad es un valor de voltaje)
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	goto	P3		;Si. (Voltaje comparado.)
	btfsc	STATUS,C	;No. Mayor (C=0)??
	goto	P3		;Si. (Mayor que voltaje comparado pero menor que voltaje anterior)
				;No, Voltaje menor

	;Comparaci�n con 2.75 voltios. Aprox: 563=(2.75*1023/5). 8bits mayores: 10001100
	movlw	b'10001100'	;Valor en C A/D equivalente al voltaje a comparar
	subwf	Presion,W	;Resta/compara con dato "Presion" (Que en realidad es un valor de voltaje)
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	goto	P4		;Si. (Voltaje comparado.)
	btfsc	STATUS,C	;No. Mayor (C=0)??
	goto	P4		;Si. (Mayor que voltaje comparado pero menor que voltaje anterior)
				;No, Voltaje menor

	;Comparaci�n con 2.50 voltios. Aprox: 511=(2.50*1023/5). 8bits mayores: 01111111
	movlw	b'01111111'	;Valor en C A/D equivalente al voltaje a comparar
	subwf	Presion,W	;Resta/compara con dato "Presion" (Que en realidad es un valor de voltaje)
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	goto	P5		;Si. (Voltaje comparado.)
	btfsc	STATUS,C	;No. Mayor (C=0)??
	goto	P5		;Si. (Mayor que voltaje comparado pero menor que voltaje anterior)
				;No, Voltaje menor

	;Comparaci�n con 2.25 voltios. Aprox: 460=(2.25*1023/5). 8bits mayores: 01110011
	movlw	b'01110011'	;Valor en C A/D equivalente al voltaje a comparar
	subwf	Presion,W	;Resta/compara con dato "Presion" (Que en realidad es un valor de voltaje)
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	goto	P6		;Si. (Voltaje comparado.)
	btfsc	STATUS,C	;No. Mayor (C=0)??
	goto	P6		;Si. (Mayor que voltaje comparado pero menor que voltaje anterior)
				;No, Voltaje menor

	;Comparaci�n con 2.00 voltios. Aprox: 409=(2.00*1023/5). 8bits mayores: 01100110
	movlw	b'01100110'	;Valor en C A/D equivalente al voltaje a comparar
	subwf	Presion,W	;Resta/compara con dato "Presion" (Que en realidad es un valor de voltaje)
	btfsc	STATUS,Z	;Son iguales (Z=1)??
	goto	P7		;Si. (Voltaje comparado.)
	btfsc	STATUS,C	;No. Mayor (C=0)??
	goto	P7		;Si. (Mayor que voltaje comparado pero menor que voltaje anterior)
	goto	P7		;No, Voltaje menor (Presi�n excesiva)


P7	movlw	b'11111111'
	goto	Muestra
P6	movlw	b'01111111'
	goto	Muestra
P5	movlw	b'00111111'
	goto	Muestra
P4	movlw	b'00011111'
	goto	Muestra
P3	movlw	b'00001111'
	goto	Muestra
P2	movlw	b'00000111'
	goto	Muestra
P1	movlw	b'00000011'
	goto	Muestra
P0	movlw	b'00000001'
	goto	Muestra
NoPres	movlw	b'00000000'

Muestra	movwf	PORTB

	return
		



; ---------------------------------------------------------------------------------------
Retardo		;Provoca un retardo segun el valor de "Posic" y "Offset"
; ---------------------------------------------------------------------------------------

;Chequeo inicial: Delay fijo de 4usg (4 ciclos)
;-------------


	movf	Posic,F		;Checkeamos si el valor es cero
	btfsc	STATUS,Z	;
	goto	DelFijo		;Si es cero salta a la parte de delay fijo
	NOP


;Primera parte: Delay variable en funci�n Posic (entre 0 y 180. 11 ciclos/grado)
;--------------

PLoop0  btfsc	PIR1,SSPIF	; Ha ocurrido un evento SSP? (I2C)
	bcf 	SSPCON,CKP	; Si. Detenemos reloj I2C para evitar desbordamiento o timeout
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	decfsz  Posic,F  	; 1 + (1) es el tiempo 0  ?
        goto    PLoop0    	; 2 no, loop
	NOP


;Segunda parte: Delay fijo dependiente del valor de Offset. Ciclos=10+5xOffset (ver definici�n macros)
;-------------

DelFijo	NOP
	movf	Offset,W     	; 1 set numero de repeticion 
        movwf	PDel0     	; 1 |
SLoop0  btfsc	PIR1,SSPIF	; Ha ocurrido un evento SSP? (I2C)
	bcf 	SSPCON,CKP	; Si. Detenemos reloj I2C para evitar desbordamiento o timeout
        decfsz	PDel0, 1  	; 1 + (1) es el tiempo 0  ?
        goto	SLoop0    	; 2 no, loop
        return              	; 2+2 Fin.


;-------------------------------------------------------------------------------
init_i2c_Slave		;Inicializa valores para uso de I2C en Slave
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
	movlw 	b'00011000'	; Establece l�neas SDA y SCL como entradas...
	iorwf 	TRISC,f		;..respetando los valores para otras l�neas.
	bcf 	SSPSTAT,CKE 	; Establece I2C input levels
	bcf 	SSPSTAT,SMP 	; Habilita slew rate
	bsf	SSPCON2,GCEN	; Habilita direccionamiento global
	movlw	DirNodo		; Direcci�n esclavo 
	movwf	SSPADD		;
	banksel SSPCON 		; Pasamos a direccionar Banco 0
	movlw 	b'00110110'	; Slave mode, SSP enable, velocidad segun...
	movwf 	SSPCON 		; ... Fosc/(4x(SSPADD+1))
	bcf	PIR1,SSPIF	; Limpia flag de eventos SSP
	bcf	PIR1,7		; Limpia bit. Mandatorio por Datasheet

	;Configuraci�n para interrupciones por evento I2C
	banksel PIE1
	bsf	PIE1,SSPIE
	bsf	INTCON,PEIE
	bsf	INTCON,GIE

	;Restauramos las copias de los registros
	movf	BkStatus,W	;Restaura las copias de registros
	movwf	STATUS		;registro de estado
	movf	BkW,W		;registro W

	return


; --------------------------------------------------------------------------------------
SSP_Handler	; Este manejador controla cada evento SSP (I2C) acontecido. 
		; The I2C code below checks for 5 states.
		; Each of the 5 SSP states discussed in this document
		; are identified by XORing the bits in the SSPSTAT register
		; with predetermined mask values. Once the state
		; has been identified, the appropriate action is taken. All
		; undefined states are handled by branching execution
		; to a software trap.

		; State 1: I2C write operation, last byte was an address byte.
		; SSPSTAT bits: S = 1, D_A = 0, R_W = 0, BF = 1

		; State 2: I2C write operation, last byte was a data byte.
		; SSPSTAT bits: S = 1, D_A = 1, R_W = 0, BF = 1

		; State 3: I2C read operation, last byte was an address byte.
		; SSPSTAT bits: S = 1, D_A = 0, R_W = 1, BF = 0

		; State 4: I2C read operation, last byte was a data byte.
		; SSPSTAT bits: S = 1, D_A = 1, R_W = 1, BF = 0

		; State 5: Slave I2C logic reset by NACK from master.
		; SSPSTAT bits: S = 1, D_A = 1, R_W = 0, BF = 0

		; For convenience, WriteI2C and ReadI2C functions have been used.
; --------------------------------------------------------------------------------------

	banksel SSPSTAT
	movf 	SSPSTAT,W 	; Get the value of SSPSTAT
	andlw 	b'00101101' 	; Mask out unimportant bits in SSPSTAT.
	banksel	Temp
	movwf 	Temp 		; for comparision checking.

State1: 			; Write operation, last byte was an
	movlw 	b'00001001' 	; address, buffer is full.
	banksel	Temp
	xorwf 	Temp,W 		;
	btfss 	STATUS,Z 	; Are we in State1?
	goto 	State2 		; No, check for next state.....
	call 	ReadI2C 	; Yes. Do a dummy read of the SSPBUF.
				; Ack is sent by hardware
	return

State2: 			; Write operation, last byte was data,
	movlw 	b'00101001' 	; buffer is full.
	banksel	Temp
	xorwf 	Temp,W
	btfss 	STATUS,Z 	; Are we in State2?
	goto 	State3 		; No, check for next state.....
	call 	ReadI2C 	; Get the byte from the SSP.

	;Aqu� tenemos en W el valor del dato recibido
	movwf	MensajeIn
	return

State3: 			; Read operation, last byte was an
	movlw 	b'00001100' 	; address, buffer is empty.
	banksel	Temp
	xorwf 	Temp,W
	btfss 	STATUS,Z 	; Are we in State3?
	goto 	State4 		; No, check for next state.....

	;Aqu� debemos poner en W el valor del dato a enviar (solicitado por el master)
	movf	MensajeOut,W

	call 	WriteI2C 	; Write the byte to SSPBUF
	return

State4: 			; Read operation, last byte was data,
	movlw 	b'00101100' 	; buffer is empty.
	banksel	Temp
	xorwf 	Temp,W
	btfss 	STATUS,Z 	; Are we in State4?
	goto 	State5 		; No, check for next state....

	;Aqu� debemos poner en W el valor del dato a enviar (solicitado por el master)
	movf	MensajeOut,W

	call 	WriteI2C 	; Write to SSPBUF
	return

State5:
	movlw 	b'00101000' 	; A NACK was received when transmitting
	banksel	Temp
	xorwf 	Temp,W 		; data back from the master. Slave logic
	btfss 	STATUS,Z 	; is reset in this case. R_W = 0, D_A = 1
	goto 	I2CErr 		; and BF = 0
	return 			; If we aren�t in State5, then something is
				; wrong.

I2CErr 	nop			; Something went wrong!
	return


;---------------------------------------------------------------------
WriteI2C	;Usada por SSP_Handler para escribir datos en bus I2C
;---------------------------------------------------------------------

	banksel SSPCON 		
	movwf 	SSPBUF 		; Write the byte in W
	bsf 	SSPCON,CKP 	; Release the clock.
	return

;---------------------------------------------------------------------
ReadI2C		;Usada por SSP_Handler para escribir datos en bus I2C
;---------------------------------------------------------------------

	banksel SSPBUF
	movf 	SSPBUF,W 	; Get the byte and put in W
	return



Fin
	END
