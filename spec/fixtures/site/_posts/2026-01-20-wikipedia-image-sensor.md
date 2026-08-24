---
title: "Image sensor"
categories: ["technology"]
tags: ["photography", "sensor", "digital", "camera"]
source: "Wikipedia — The Free Encyclopedia"
source_url: "https://en.wikipedia.org/wiki/Image_sensor"
download_date: "2026-08-22"
license: "CC BY-SA 3.0"
---

An image sensor or imager is a sensor used for imaging. It detects and conveys information used to form an image. It does so by converting the variable attenuation of light waves (as they pass through or reflect off objects) into signals, small bursts of current that convey the information. The waves can be light or other electromagnetic radiation. Image sensors are used in electronic imaging devices of both analog and digital types, which include digital cameras, camera modules, camera phones, optical mouse devices, medical imaging equipment, night vision equipment such as thermal imaging devices, radar, sonar, and others. As technology changes, electronic and digital imaging tends to replace chemical and analog imaging.
The two main types of electronic image sensors are the charge-coupled device (CCD) and the active-pixel sensor (CMOS sensor). Both CCD and CMOS sensors are based on metal–oxide–semiconductor (MOS) technology, with CCDs based on MOS capacitors and CMOS sensors based on MOSFET (MOS field-effect transistor) amplifiers. Analog sensors for invisible radiation tend to involve vacuum tubes of various kinds, while digital sensors include flat-panel detectors. Commonly, an image sensor requires a lens to project images onto the image sensor, so they can be captured, as done in a camera. Image sensors that require no lens have been developed. Pixels in image sensors can be damaged by high-power lasers.


== Comparison between CCD and CMOS sensors ==

The two main types of digital image sensors are the charge-coupled device (CCD) and the active-pixel sensor (CMOS sensor), fabricated in complementary MOS (CMOS) or N-type MOS (NMOS or Live MOS) technologies. Both CCD and CMOS sensors are based on the MOS technology, with MOS capacitors being the building blocks of a CCD, and MOSFET amplifiers being the building blocks of a CMOS sensor.
Cameras integrated in small consumer products generally use CMOS sensors, which are usually cheaper and have lower power consumption in battery powered devices than CCDs. CCD sensors are used for high end broadcast quality video cameras, and CMOS sensors dominate in still photography and consumer goods where overall cost is a major concern. Both types of sensor accomplish the same task of capturing light and converting it into electrical signals.
Each cell of a CCD image sensor is an analog device, a pinned photodiode. When light strikes the chip it is held as a small electrical charge in each photodiode. The charges in the line of pixels nearest to the (one or more) output amplifiers are amplified and output, then each line of pixels shifts its charges one line closer to the amplifiers, filling the empty line closest to the amplifiers. This process is then repeated until all the lines of pixels have had their charge amplified and output.
A CMOS image sensor has an amplifier for each pixel compared to the few amplifiers of a CCD. This results in less area for the capture of photons than a CCD, but this problem has been overcome by using microlenses in front of each photodiode, which focus light into the photodiode that would have otherwise hit the amplifier and not been detected. Behind each microlens sits a color filter made of special colored photoresist. Some CMOS imaging sensors also use back-side illumination to increase the number of photons that hit the photodiode. CMOS sensors can potentially be implemented with fewer components, use less power, and/or provide faster readout than CCD sensors. They are also less vulnerable to static electricity discharges.
Another design, a hybrid CCD/CMOS architecture (sold under the name "sCMOS") consists of CMOS readout integrated circuits (ROICs) that are bump bonded to a CCD imaging substrate – a technology that was developed for infrared staring arrays and has been adapted to silicon-based detector technology. Another approach is to utilize the very fine dimensions available in modern CMOS technology to implement a CCD like structure entirely in CMOS technology: such structures can be achieved by separating individual poly-silicon gates by a very small gap; though still a product of research hybrid sensors can potentially harness the benefits of both CCD and CMOS imagers.


== Performance ==

There are many parameters that can be used to evaluate the performance of an image sensor, including dynamic range, signal-to-noise ratio, and low-light sensitivity. For sensors of comparable types, the signal-to-noise ratio and dynamic range improve as the size increases. It is because in a given integration (exposure) time, more photons hit the pixel with larger area.


== Exposure-time control ==
Exposure time of image sensors is generally controlled by either a conventional mechanical shutter, as in film cameras, or by an electronic shutter. Electronic shuttering can be "global," in which case the entire image sensor area's accumulation of photoelectrons starts and stops simultaneously, or "rolling" in which case the exposure interval of each row immediately precedes that row's readout, in a process that "rolls" across the image frame (typically from top to bottom in landscape format). Global electronic shuttering is less common, as it requires "storage" circuits to hold charge from the end of the exposure interval until the readout process gets there, typically a few milliseconds later.


== Color separation ==

There are several main types of color image sensors, differing by the type of color-separation mechanism:

Integral color sensors use a color filter array fabricated on top of a single monochrome CCD or CMOS image sensor. The most common color filter array pattern, the Bayer pattern, uses a checkerboard arrangement of two green pixels for each red and blue pixel, although many other color filter patterns have been developed, including patterns using cyan, magenta, yellow, and white pixels. Integral color sensors were initially manufactured by transferring colored dyes through photoresist windows onto a polymer receiving layer coated on top of a monochrome CCD sensor. Since each pixel provides only a single color (such as green), the "missing" color values (such as red and blue) for the pixel are interpolated using neighboring pixels. This processing is also referred to as demosaicing or de-bayering. Some image sensors have a high pixel count, but to offset their disadvantages such as low light sensitivity and dynamic range under normal shooting conditions, they resort to pixel binning, in which the sensor reads 4 or 9 adjacent pixels as one group, and all groups have the same color filter color.
Foveon X3 sensor, using an array of layered pixel sensors, separating light via the inherent wavelength-dependent absorption property of silicon, such that every location senses all three color channels. This method is similar to how color film for photography works.
3CCD, using three discrete image sensors, with the color separation done by a dichroic prism. The dichroic elements provide a sharper color separation, thus improving color quality. Because each sensor is equally sensitive within its passband, and at full resolution, 3-CCD sensors produce better color quality and better low light performance. 3-CCD sensors produce a full 4:4:4 signal, which is preferred in television broadcasting, video editing and chroma key visual effects.


== Specialty sensors ==

Special sensors are used in various applications such as creation of multi-spectral images, video laryngoscopes, gamma cameras, Flat-panel detectors and other sensor arrays for x-rays, microbolometer arrays in thermography, and other highly sensitive arrays for astronomy.
While in general, digital cameras use a flat sensor, Sony prototyped a curved sensor in 2014 to reduce/eliminate Petzval field curvature that occurs with a flat sensor. Use of a curved sensor allows a shorter and smaller diameter of the lens with reduced elements and components with greater aperture and reduced light fall-off at the edge of the photo.


== Lenless sensing ==
Lenses focus light onto a camera's sensor as an image. Lenless sensors substitute alternative optical components and computational technologies to form images. For example, a coded aperture, zone platem, or diffraction grating can replace the lens. These systems can reduce manufacturing cost and allow thin optical path lengths, as well as high light throughput and application across broader frequency ranges.


== History ==

Early analog sensors for visible light were video camera tubes. They date back to the 1930s, and several types were developed up until the 1980s. By the early 1990s, they had been replaced by modern solid-state CCD image sensors.
The basis for modern solid-state image sensors is MOS technology, which originates from the invention of the MOSFET by Mohamed M. Atalla and Dawon Kahng at Bell Labs in 1959. Later research on MOS technology led to the development of solid-state semiconductor image sensors, including the charge-coupled device (CCD) and later the active-pixel sensor (CMOS sensor).
The passive-pixel sensor (PPS) was the precursor to the active-pixel sensor (APS). A PPS consists of passive pixels which are read out without amplification, with each pixel consisting of a photodiode and a MOSFET switch. It is a type of photodiode array, with pixels containing a p-n junction, integrated capacitor, and MOSFETs as selection transistors. A photodiode array was proposed by G. Weckler in 1968. This was the basis for the PPS. These early photodiode arrays were complex and impractical, requiring selection transistors to be fabricated within each pixel, along with on-chip multiplexer circuits. The noise of photodiode arrays was also a limitation to performance, as the photodiode readout bus capacitance resulted in increased noise level. Correlated double sampling (CDS) could also not be used with a photodiode array without external memory.
In June 2022, Samsung Electronics announced that it had created a 200 million pixel image sensor. The 200MP ISOCELL HP3 has 0.56 micrometer pixels with Samsung reporting that previous sensors had 0.64 micrometer pixels, a 12% decrease since 2019. The new sensor contains 200 million pixels in a 1-by-1.4-inch (25 by 36 mm) lens.


=== Charge-coupled device ===

The charge-coupled device (CCD) was invented by Willard S. Boyle and George E. Smith at Bell Labs in 1969. While researching MOS technology, they realized that an electric charge was the analogy of the magnetic bubble and that it could be stored on a tiny MOS capacitor. As it was fairly straightforward to fabricate a series of MOS capacitors in a row, they connected a suitable voltage to them so that the charge could be stepped along from one to the next. The CCD is a semiconductor circuit that was later used in the first digital video cameras for television broadcasting.
Early CCD sensors suffered from shutter lag. This was largely resolved with the invention of the pinned photodiode (PPD). It was invented by Nobukazu Teranishi, Hiromitsu Shiraki and Yasuo Ishihara at NEC in 1980. It was a photodetector structure with low lag, low noise, high quantum efficiency and low dark current. In 1987, the PPD began to be incorporated into most CCD devices, becoming a fixture in consumer electronic video cameras and then digital still cameras. Since then, the PPD has been used in nearly all CCD sensors and then CMOS sensors.


=== Active-pixel sensor ===

The NMOS active-pixel sensor (APS) was invented by Olympus in Japan during the mid-1980s. This was enabled by advances in MOS semiconductor device fabrication, with MOSFET scaling reaching smaller micron and then sub-micron levels. The first NMOS APS was fabricated by Tsutomu Nakamura's team at Olympus in 1985. The CMOS active-pixel sensor (CMOS sensor) was later improved by a group of scientists at the NASA Jet Propulsion Laboratory in 1993. By 2007, sales of CMOS sensors had surpassed CCD sensors. By the 2010s, CMOS sensors largely displaced CCD sensors in all new applications.


=== Other image sensors ===
The first commercial digital camera, the Cromemco Cyclops in 1975, used a 32×32 MOS image sensor. It was a modified MOS dynamic RAM (DRAM) memory chip.
MOS image sensors are widely used in optical mouse technology. The first optical mouse, invented by Richard F. Lyon at Xerox in 1980, used a 5 μm NMOS integrated circuit sensor chip. Since the first commercial optical mouse, the IntelliMouse introduced in 1999, most optical mouse devices use CMOS sensors.
In February 2018, researchers at Dartmouth College announced a new image sensing technology that the researchers call QIS, for Quanta Image Sensor. Instead of pixels, QIS chips have what the researchers call "jots." Each jot can detect a single particle of light, called a photon.


== See also ==
List of sensors used in digital cameras
Contact image sensor (CIS)
Electro-optical sensor
Video camera tube, used before image sensors for video
Semiconductor detector
Fill factor
Full-frame digital SLR
Image resolution
Image sensor format, the sizes and shapes of common image sensors
Color filter array, mosaic of tiny color filters over color image sensors
Sensitometry, the scientific study of light-sensitive materials
History of television, the development of electronic imaging technology since the 1880s
List of large sensor interchangeable-lens video cameras
Oversampled binary image sensor
Computer vision
Push broom scanner
Whisk broom scanner


== References ==


== External links ==
Digital Camera Sensor Performance Summary by Roger Clark
Clark, Roger. "Does Pixel Size Matter?". clarkvision.com. (with graphical buckets and rainwater analogies)
