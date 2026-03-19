// Setup video and canvas
const video = document.createElement("video");
const canvasElement = document.getElementById("canvas");
const canvas = canvasElement.getContext("2d");

// Request camera access
navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } }).then((stream) => {
  video.srcObject = stream;
  video.setAttribute("playsinline", true); // Required for iOS
  video.play();
  requestAnimationFrame(tick);
});

function tick() {
  let cont = true;
  if (video.readyState === video.HAVE_ENOUGH_DATA) {
    canvasElement.height = video.videoHeight;
    canvasElement.width = video.videoWidth;
    canvas.drawImage(video, 0, 0, canvasElement.width, canvasElement.height);
    
    const imageData = canvas.getImageData(0, 0, canvasElement.width, canvasElement.height);
    const code = jsQR(imageData.data, imageData.width, imageData.height);

    if (code && code.binaryData.length) {
      // code.data provides the string version
      // code.binaryData provides the raw Uint8ClampedArray
      let base64 = new Uint8Array(code.binaryData).toBase64();
      console.log(base64);

      let overlay = document.getElementById("overlay");
      overlay.hidden = false;
      fetch("/verify", {
        method: "POST",
        body: JSON.stringify({
          data: base64,
          seed: document.getElementById("seed").innerText
        }),
        headers: {
          "Content-type": "application/json; charset=UTF-8"
        }
      }).then((resp) => {
        console.log(resp);
        if (resp.status == 200) {
          overlay.classList.add("success");
          overlay.innerText = "Verified";
        } else if (resp.status == 499) {
          overlay.classList.add("signfail");
          overlay.innerText = "Signature failure";
        } else {
          overlay.classList.add("fail");
          overlay.innerText = "Unknown failure";
        }
      });

      cont = false;
    }
  }
  if (cont) {
    requestAnimationFrame(tick);
  } else {
    document.getElementById("canvas").hidden = true;
  }
}

function makeid(length) {
    var result           = '';
    var characters       = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    var charactersLength = characters.length;
    for ( var i = 0; i < length; i++ ) {
        result += characters.charAt(Math.floor(Math.random() * charactersLength));
    }
    return result;
}

document.addEventListener("DOMContentLoaded", () => {
  document.getElementById("seed").innerText = makeid(10);
});
