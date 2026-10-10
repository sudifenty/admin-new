/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        smartple: {
          blue: '#0D6EFD',
          ink: '#17263C',
          canvas: '#F8F9FA',
        },
      },
      borderRadius: { card: '16px' },
    },
  },
  plugins: [],
};
