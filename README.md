
<html>

<head>
<meta http-equiv="Content-Language" content="es">
<meta name="GENERATOR" content="Microsoft FrontPage 4.0">
<meta name="ProgId" content="FrontPage.Editor.Document">
</head>

<font size="4"><b><i>Melanie-0&nbsp;</i></b></font>
      <p>Por Alejandro Alonso Puig<br>
      Abril 2003<br>
 
<hr>
<p align="justify"><br>
Primer prototipo del robot hexápodo Melanie.<br><br>
Melanie-0 fue un prototipo inicial de la saga de robots hexápodos "Melanie". Esta versión se movía, pero era incapaz de sostener su propio cuerpo.<br>
 El diseño se realizó separando el robot por módulos, de manera que cada pata estaba controlada por un microcontrolador y los seis microcontroladores estaban a su vez controlados por un microcontrolador central o master. Todo ellos modelo PIC16F876 de Microchip technologies.<br>
 Tras construirlo se vió que el diseño mecánico no era el óptimo, los motores no eran suficientemente potentes y los movimientos eran muy bruscos.<br>
 Por ello este proyecto evolucionó a Melanie-I y posteriormente a Melanie-II y Melanie-III.
<br>
 <p align="center"><img border="0" src="Media\CIMG0032.JPG" width="600" ></p>
<br>
En este repositorio puede encontrarse el código fuente de cada pata y del master en ensamblador, imágenes y vídeos. No hay esquemas eléctricos, pero básicamente eran módulos que se conectaban a los tres servos y a un puerto I2C común. El código está bastante documentado y se puede averiguar a qué estaba conectado cada pin del microcontrolador por los comentarios del código.<br>

<ul>
  <li><p align="justify"><a href="Media">Fotos y vídeos</a></li>
  <li><p align="justify"><a href="https://github.com/aalonsopuig/Melanie-I_Hexapod_Robot.git">Repositorio Melanie-I</a></li>
  <li><p align="justify"><a href="https://github.com/aalonsopuig/Melanie-II_Hexapod_Robot.git">Repositorio Melanie-II</a></li>
  <li><p align="justify"><a href="https://github.com/aalonsopuig/Melanie-III_Hexapod_Robot.git">Repositorio Melanie-III</a></li>
</ul>


</body>

</html>
