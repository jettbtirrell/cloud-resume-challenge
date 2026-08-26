(function () {
    const triggers = document.querySelectorAll('.video-demo-trigger');
    const preview = document.getElementById('video-preview');
    const modal = document.getElementById('video-modal');
    const modalPlayer = document.getElementById('video-modal-player');
    const modalClose = document.getElementById('video-modal-close');

    if (!triggers.length || !preview || !modal || !modalPlayer || !modalClose) return;

    const OFFSET_X = 24;
    const OFFSET_Y = 24;

    function positionPreview(e) {
        const rect = preview.getBoundingClientRect();
        let x = e.clientX + OFFSET_X;
        let y = e.clientY + OFFSET_Y;

        if (x + rect.width > window.innerWidth) {
            x = e.clientX - rect.width - OFFSET_X;
        }
        if (y + rect.height > window.innerHeight) {
            y = e.clientY - rect.height - OFFSET_Y;
        }

        preview.style.transform = `translate(${x}px, ${y}px)`;
    }

    function closeModal() {
        modal.classList.remove('visible');
        modalPlayer.pause();
    }

    triggers.forEach((trigger) => {
        const videoSrc = trigger.dataset.video;
        if (!videoSrc) return;

        trigger.addEventListener('mouseenter', (e) => {
            if (preview.getAttribute('src') !== videoSrc) preview.setAttribute('src', videoSrc);
            preview.classList.add('visible');
            positionPreview(e);
            preview.currentTime = 0;
            preview.play().catch(() => {});
        });

        trigger.addEventListener('mousemove', positionPreview);

        trigger.addEventListener('mouseleave', () => {
            preview.classList.remove('visible');
            preview.pause();
        });

        function openModal() {
            preview.classList.remove('visible');
            preview.pause();
            if (modalPlayer.getAttribute('src') !== videoSrc) modalPlayer.setAttribute('src', videoSrc);
            modal.classList.add('visible');
            modalPlayer.currentTime = 0;
            modalPlayer.play().catch(() => {});
        }

        trigger.addEventListener('click', openModal);
        trigger.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                openModal();
            }
        });
    });

    modalClose.addEventListener('click', closeModal);
    modal.addEventListener('click', (e) => {
        if (e.target === modal) closeModal();
    });
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && modal.classList.contains('visible')) closeModal();
    });
})();
