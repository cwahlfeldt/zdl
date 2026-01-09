// ZDL Module Demo
// Demonstrates ES6 import support for the ZDL engine

import zdl from "zdl";

console.log("ZDL Module Demo");
console.log("Testing import support...");

// Test window creation
// This queues a window configuration that Zig can retrieve and process.
// The JavaScript->Zig communication works via a command queue pattern.
const window = zdl.createWindow({
  size: "800x600",
  title: "Module Demo"
});

console.log("Window created:", window.title, window.width + "x" + window.height);

// Test world creation
const world = zdl.createWorld(window);

console.log("World created successfully!");
console.log("Import support is working!");
