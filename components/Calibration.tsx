import React, { useState, useMemo } from 'react';

interface CalibrationProps {
  onComplete: (dpi: number) => void;
}

// A standard fallback DPI, often used by browsers.
const BASE_DPI = 96;

const Calibration: React.FC<CalibrationProps> = ({ onComplete }) => {
  // The slider value represents a scaling factor for the base DPI.
  // It starts at 1, representing the default 96 DPI.
  const [scale, setScale] = useState(1);

  // The calculated DPI updates as the user moves the slider.
  const currentDpi = useMemo(() => BASE_DPI * scale, [scale]);

  const handleDone = () => {
    onComplete(currentDpi);
  };

  return (
    <div className="absolute inset-0 bg-black bg-opacity-80 flex flex-col items-center justify-center z-50 text-white font-sans p-4">
      <div className="bg-gray-800 p-8 rounded-lg shadow-2xl max-w-sm w-full text-center flex flex-col gap-6">
        <h2 className="text-2xl font-bold">Screen Calibration</h2>
        <p className="text-gray-300">
          Hold a physical ruler up to your screen. Adjust the slider until the white box below is exactly <span className="font-bold text-white">1 inch</span> wide.
        </p>

        {/* The reference box that the user measures */}
        <div className="w-full h-20 bg-gray-900 rounded flex items-center justify-center p-2">
            <div
                className="bg-white h-1/2 transition-all duration-50"
                style={{ width: `${currentDpi}px` }}
                aria-hidden="true"
            ></div>
        </div>

        <div className="w-full">
            <input
              type="range"
              min="0.5" // Allows for screens with lower than 96 DPI
              max="2.5" // Allows for high-resolution screens
              step="0.01"
              value={scale}
              onChange={(e) => setScale(parseFloat(e.target.value))}
              className="w-full h-2 bg-gray-600 rounded-lg appearance-none cursor-pointer"
              aria-label="Screen calibration slider"
            />
        </div>

        <button
          onClick={handleDone}
          className="bg-blue-600 hover:bg-blue-700 text-white font-bold py-3 px-6 rounded-lg transition-colors text-lg"
        >
          Done
        </button>
      </div>
    </div>
  );
};

export default Calibration;
