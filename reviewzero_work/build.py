# -*- coding: utf-8 -*-
import defusedxml.minidom as MD
from xml.sax.saxutils import escape

A = "http://schemas.openxmlformats.org/drawingml/2006/main"
FONT = ('<a:latin typeface="Times New Roman" panose="02020603050405020304" pitchFamily="18" charset="0"/>'
        '<a:cs typeface="Times New Roman" panose="02020603050405020304" pitchFamily="18" charset="0"/>')

def run(text, sz, b=False, i=False):
    rpr = '<a:rPr lang="en-IN" sz="%d"%s%s dirty="0">%s</a:rPr>' % (
        sz, ' b="1"' if b else '', ' i="1"' if i else '', FONT)
    sp = ' xml:space="preserve"' if (text[:1] == ' ' or text[-1:] == ' ') else ''
    return '<a:r>%s<a:t%s>%s</a:t></a:r>' % (rpr, sp, escape(text))

def para(runs, lvl=0, bullet=True, spc=300):
    # runs: list of run-xml strings
    bu = '' if bullet else '<a:buNone/>'
    ppr = '<a:pPr lvl="%d"><a:spcAft><a:spcPts val="%d"/></a:spcAft>%s</a:pPr>' % (lvl, spc, bu)
    return '<a:p>%s%s</a:p>' % (ppr, ''.join(runs))

def header(text, sz=1600, spc=300):
    return para([run(text, sz, b=True)], lvl=0, bullet=False, spc=spc)

def bullet(text, sz, spc=300, lvl=0):
    return para([run(text, sz)], lvl=lvl, bullet=True, spc=spc)

def bullet_lbl(label, rest, sz, spc=300):
    return para([run(label, sz, b=True), run(rest, sz)], lvl=0, bullet=True, spc=spc)

# ---------------- content ----------------
SL = {}

SL[3] = [
    bullet("NRK Air Services is an AI-enabled aerial logistics platform that uses autonomous drones, computer vision, and geospatial intelligence to deliver goods and emergency medical supplies across India.", 1800, 500),
    bullet_lbl("Challenge: ", "heavy dependence on road transport causes traffic delays, high fuel use and emissions, and poor access to remote and disaster-affected zones.", 1800, 500),
    bullet_lbl("Solution: ", "it integrates AI, computer vision, geospatial intelligence, autonomous drones, and cloud-based fleet management into a single last-mile delivery system.", 1800, 500),
    bullet_lbl("Core innovation: ", "a trimodal Geo-Vision pipeline that fuses a ground photo, a text landmark description, and GPS to verify the exact delivery location — even in GPS-denied areas.", 1800, 500),
    bullet_lbl("Impact: ", "faster deliveries, lower operational cost and carbon emissions, and reliable emergency transport of medicines, blood, and vaccines.", 1800, 500),
]

SL[4] = [
    header("Problem Statement", 1600, 150),
    bullet("Traffic-induced congestion delays last-mile and emergency deliveries.", 1500, 150),
    bullet("GPS-only drone navigation lacks intelligent visual verification for precise, address-level delivery.", 1500, 150),
    bullet("High fuel and labour dependency raise operating cost and carbon emissions.", 1500, 150),
    bullet("Remote, rural, and disaster-hit areas face delayed access to critical supplies.", 1500, 300),
    header("Objectives", 1600, 150),
    bullet("Deploy autonomous drones to bypass road congestion and speed up last-mile and emergency delivery.", 1500, 150),
    bullet("Build a Geo-Vision trimodal pipeline (ground photo + text landmark + GPS) for precise, verifiable delivery in GPS-denied zones.", 1500, 150),
    bullet("Reduce fuel and labour dependency, operating cost, and carbon emissions through electric aerial logistics.", 1500, 150),
    bullet("Ensure reliable delivery of medicines, blood, and vaccines to remote, rural, and disaster areas.", 1500, 150),
    bullet("Demonstrate a lightweight edge-offload architecture running cross-view matching on low-cost ESP32-class drone hardware.", 1500, 150),
]

SL[5] = [
    header("Existing Systems", 1500, 120),
    bullet_lbl("Cross-view geo-localization ", "(University-1652 [1], VIGOR [2]) established UAV-to-ground image matching, but only for structured Western cities.", 1350, 120),
    bullet_lbl("Vision-language models ", "(CLIP [3]) enable place recognition, yet match a single modality — no fusion of text + image + GPS.", 1350, 120),
    bullet_lbl("UAV last-mile delivery ", "(Zipline, Wing [7]) is operationally proven but GPS-only, with no visual delivery confirmation.", 1350, 120),
    bullet_lbl("AI routing and edge AI ", "(2023–2025) improve dynamic route planning and real-time on-board obstacle avoidance.", 1350, 120),
    bullet_lbl("Indian scene datasets ", "(IDD [4]) cover road driving only — no aerial-to-ground data for Indian rooftops or landmarks.", 1350, 300),
    header("Research Gap addressed by NRK", 1500, 120),
    bullet("No India-specific cross-view dataset → NRK captures rooftops, compound walls, water tanks, and landmark addresses.", 1350, 120),
    bullet("No multimodal address verification → NRK fuses ground photo + text + GPS (trimodal).", 1350, 120),
    bullet("GPS-denied final-meter problem → NRK adds a visual-language matching fallback.", 1350, 120),
    bullet("No edge-offload verification → NRK runs cross-view matching on ESP32 drones via server offloading.", 1350, 120),
]

SL[6] = [
    header("Hardware", 1600, 150),
    bullet("Autonomous drone airframe (quad/hexacopter) with BLDC motors, ESCs, and propellers.", 1400, 150),
    bullet("ESP32-class microcontroller for low-cost on-board (edge) compute with a Pixhawk / PX4 flight controller.", 1400, 150),
    bullet("GPS/GNSS module, IMU, and obstacle-detection sensors (ultrasonic / LiDAR).", 1400, 150),
    bullet("Onboard camera module for ground-image capture and computer vision.", 1400, 150),
    bullet("LiPo battery, power-management unit, and telemetry / 4G-LTE communication link.", 1400, 150),
    bullet("Ground GPU server/workstation (e.g., NVIDIA GPU) for model training and offloaded inference.", 1400, 300),
    header("Software", 1600, 150),
    bullet("Python with PyTorch / TensorFlow for the cross-view and vision-language (CLIP) models.", 1400, 150),
    bullet("OpenCV for computer vision; GDAL / GeoPandas and mapping APIs for geospatial route optimization.", 1400, 150),
    bullet("ArduPilot / PX4 firmware and ESP-IDF for flight and edge control.", 1400, 150),
    bullet("Flutter mobile app for order placement, image upload, and real-time tracking.", 1400, 150),
    bullet("Cloud platform (AWS / Azure / GCP) with REST APIs for fleet management.", 1400, 150),
    bullet("Database (MongoDB / PostgreSQL) with a web dashboard for analytics and reporting.", 1400, 150),
]

SL[7] = [
    para([run("Indicative plan (Review 0 → final submission). Durations are in project weeks.", 1400, i=True)], lvl=0, bullet=False, spc=300),
    bullet_lbl("Phase 1 – Requirement Analysis & Literature Survey (Weeks 1–3): ", "finalize scope and study existing cross-view and UAV-delivery work.", 1500, 250),
    bullet_lbl("Phase 2 – Dataset Collection & Annotation (Weeks 4–7): ", "build the India-specific cross-view dataset (rooftops, landmarks, compound walls).", 1500, 250),
    bullet_lbl("Phase 3 – Model Development (Weeks 8–12): ", "train the trimodal fusion pipeline (ground photo + text + GPS).", 1500, 250),
    bullet_lbl("Phase 4 – Edge-Offload & Drone Integration (Weeks 13–16): ", "run cross-view matching on ESP32-class hardware with server offloading.", 1500, 250),
    bullet_lbl("Phase 5 – System Integration (Weeks 17–19): ", "connect cloud fleet management, mobile app, and delivery-validation module.", 1500, 250),
    bullet_lbl("Phase 6 – Testing & Field Trials (Weeks 20–22): ", "validate accuracy, obstacle avoidance, and GPS-denied delivery.", 1500, 250),
    bullet_lbl("Phase 7 – Evaluation & Documentation (Weeks 23–24): ", "analyze results and prepare the report and final review.", 1500, 250),
]

refs = [
    'Z. Zheng, Y. Wei, and Y. Yang, "University-1652: A multi-view multi-source benchmark for drone-based geo-localization," in Proc. 28th ACM Int. Conf. Multimedia (MM), 2020, pp. 1395–1403.',
    'S. Zhu, T. Yang, and C. Chen, "VIGOR: Cross-view image geo-localization beyond one-to-one retrieval," in Proc. IEEE/CVF Conf. Computer Vision and Pattern Recognition (CVPR), 2021, pp. 3640–3649.',
    'A. Radford et al., "Learning transferable visual models from natural language supervision," in Proc. 38th Int. Conf. Machine Learning (ICML), 2021, pp. 8748–8763.',
    'G. Varma, A. Subramanian, A. Namboodiri, M. Chandraker, and C. V. Jawahar, "IDD: A dataset for exploring problems of autonomous navigation in unconstrained environments," in Proc. IEEE Winter Conf. Applications of Computer Vision (WACV), 2019, pp. 1743–1751.',
    'H. Shakhatreh et al., "Unmanned aerial vehicles (UAVs): A survey on civil applications and key research challenges," IEEE Access, vol. 7, pp. 48572–48634, 2019.',
    'M. Mozaffari, W. Saad, M. Bennis, Y.-H. Nam, and M. Debbah, "A tutorial on UAVs for wireless networks: Applications, challenges, and open problems," IEEE Commun. Surveys Tuts., vol. 21, no. 3, pp. 2334–2360, 2019.',
    'E. Ackerman and E. Strickland, "Medical delivery drones take flight in East Africa," IEEE Spectrum, vol. 55, no. 1, pp. 34–35, Jan. 2018.',
    'S. A. H. Mohsan et al., "Unmanned aerial vehicles (UAVs): practical aspects, applications, open challenges, security issues, and future trends," Intelligent Service Robotics, vol. 16, pp. 109–137, 2023.',
]
SL[8] = [para([run("[%d]  " % (n+1), 1300, b=True), run(r, 1300)], lvl=0, bullet=False, spc=250)
         for n, r in enumerate(refs)]

# ---------------- inject ----------------
def frag_children(xml_paras):
    wrap = '<root xmlns:a="%s">%s</root>' % (A, ''.join(xml_paras))
    doc = MD.parseString(wrap)
    return list(doc.documentElement.childNodes)

for num, paras in SL.items():
    path = 'unpacked/ppt/slides/slide%d.xml' % num
    doc = MD.parse(path)
    # find body placeholder sp
    body_txbody = None
    for sp in doc.getElementsByTagNameNS(A.replace('drawingml','presentationml') if False else "http://schemas.openxmlformats.org/presentationml/2006/main", 'sp'):
        phs = sp.getElementsByTagNameNS("http://schemas.openxmlformats.org/presentationml/2006/main", 'ph')
        if phs and phs[0].getAttribute('type') == 'body':
            body_txbody = sp.getElementsByTagNameNS("http://schemas.openxmlformats.org/presentationml/2006/main", 'txBody')[0]
            break
    assert body_txbody is not None, "no body on slide %d" % num
    # remove existing <a:p>
    for p in list(body_txbody.getElementsByTagNameNS(A, 'p')):
        if p.parentNode is body_txbody:
            body_txbody.removeChild(p)
    # append new paragraphs
    for node in frag_children(paras):
        body_txbody.appendChild(node.cloneNode(True))
    with open(path, 'w', encoding='utf-8') as f:
        f.write(doc.toxml())
    print("wrote slide", num, "paras", len(paras))
print("DONE")
