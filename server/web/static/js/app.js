let content = "";

function applyDiff(diff) {
  // Simple diff application logic (you might want to use a more robust diff library)
  const lines = diff.split("\n");
  lines.forEach((line) => {
    if (line.startsWith("+")) {
      content += line.slice(1) + "\n";
    } else if (line.startsWith("-")) {
      content = content.replace(line.slice(1) + "\n", "");
    }
  });
  updateContent();
}

function updateContent() {
  document.getElementById("content").innerHTML = marked.parse(content);
}

const socket = new WebSocket(
  `ws://${window.location.host}${window.location.pathname}`,
);

socket.onmessage = function (event) {
  applyDiff(event.data);
};

socket.onopen = function () {
  console.log("Connected to WebSocket");
};

socket.onerror = function (error) {
  console.error("WebSocket Error:", error);
};

socket.onclose = function () {
  console.log("WebSocket connection closed");
};
